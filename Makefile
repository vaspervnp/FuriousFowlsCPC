# ============================================================================
#  FURIOUS FOWLS — Amstrad CPC build pipeline (Linux)
#
#  Targets:
#    make               assemble + build the bootable DSK (default)
#    make asm           assemble only  -> build/FOWLS.BIN, build/FOWLART.BIN
#    make dsk           disk image     -> dist/fowls.dsk
#    make sprites-export  write assets/sheets/*.png so you can edit the art
#    make levels-export   write assets/levels/*.txt so you can edit the forts
#    make check-state   state.inc overlaps, and theme skies vs the pens
#    make manual        render docs/manual*.md -> docs/*.pdf
#    make cover         draw the sleeve art     -> docs/cover*.png
#    make run           launch dist/fowls.dsk in RetroVirtualMachine
#    make clean         remove build/ and dist/
#
#  The sheets and the level files are the SOURCE OF TRUTH. The *-export
#  targets only write files that do not exist yet; add FORCE=1 to overwrite
#  them with the built-in defaults (which throws away your edits).
#
#  Toolchain: RASM (assembler), iDSK (DSK tool). Override with RASM=/IDSK=.
# ============================================================================

RASM      ?= rasm
IDSK      ?= iDSK
RVM       ?= RetroVirtualMachine
PYTHON    ?= python3

SRCDIR    := src
BUILD     := build
DIST      := dist

# uppercase basenames: iDSK derives the AMSDOS catalogue name from them
BIN       := $(BUILD)/FOWLS.BIN
SYM       := $(BUILD)/fowls.sym
ARTBIN    := $(BUILD)/FOWLART.BIN
ARTSYM    := $(BUILD)/fowlart.sym
LOADER    := $(BUILD)/FOWLS.BAS
SPLASH    := $(BUILD)/REVIVE8B.SCR
SCORES    := $(BUILD)/SCORES.BIN
DSK       := $(DIST)/fowls.dsk

SOURCES   := $(wildcard $(SRCDIR)/*.asm) $(wildcard $(SRCDIR)/*.inc)
SHEETS    := $(wildcard assets/sheets/*.png)
LEVELTXT  := $(wildcard assets/levels/*.txt)
SOUNDTXT  := assets/sounds.txt
MUSICTXT  := assets/music.txt

ART_OUT   := $(BUILD)/creatures.raw $(BUILD)/blocks.raw $(BUILD)/scenofs.raw \
             $(BUILD)/scenery.raw $(BUILD)/art_defs.inc $(BUILD)/art_tables.inc
LVL_OUT   := $(BUILD)/levels.raw $(BUILD)/level_defs.inc \
             $(BUILD)/level_tables.inc
SND_OUT   := $(BUILD)/sounds.raw $(BUILD)/sound_defs.inc \
             $(BUILD)/music.raw $(BUILD)/music_defs.inc
TABLES    := $(BUILD)/tables.inc $(BUILD)/sin.raw $(BUILD)/font.raw \
             $(BUILD)/rot_tables.inc $(BUILD)/rot_defs.inc
GENERATED := $(ART_OUT) $(LVL_OUT) $(TABLES) $(SND_OUT)

ifdef FORCE
FORCEFLAG := --force
endif

LOAD_ADDR := 4000
EXEC_ADDR := 4000
ART_ADDR  := C000

.PHONY: all asm dsk run clean sprites-export levels-export sounds-export \
        art levels sounds manual cover docs check-state

all: dsk

# ---- art: spritesheets in, packed banks out --------------------------------
sprites-export:
	$(PYTHON) tools/mksheets.py $(FORCEFLAG)

levels-export:
	$(PYTHON) tools/levels.py --export $(FORCEFLAG)

$(ART_OUT): tools/gen_art.py tools/artlib.py tools/sheetdefs.py $(SHEETS)
	@mkdir -p $(BUILD)
	@test -n "$(SHEETS)" || $(PYTHON) tools/mksheets.py
	$(PYTHON) tools/gen_art.py

$(LVL_OUT): tools/levels.py tools/sheetdefs.py $(LEVELTXT)
	@mkdir -p $(BUILD)
	@test -n "$(LEVELTXT)" || $(PYTHON) tools/levels.py --export
	$(PYTHON) tools/levels.py

$(BUILD)/tables.inc $(BUILD)/sin.raw $(BUILD)/font.raw: tools/gen_tables.py
	@mkdir -p $(BUILD)
	$(PYTHON) tools/gen_tables.py $(BUILD) > $(BUILD)/tables.inc

$(BUILD)/rot_tables.inc $(BUILD)/rot_defs.inc: tools/gen_rot.py
	@mkdir -p $(BUILD)
	$(PYTHON) tools/gen_rot.py > $(BUILD)/rot_tables.inc

art: $(ART_OUT)
levels: $(LVL_OUT)

# ---- assemble --------------------------------------------------------------
asm: $(BIN) $(ARTBIN)

$(BIN): $(SOURCES) $(GENERATED) Makefile
	@mkdir -p $(BUILD)
	$(PYTHON) tools/checkstate.py
	$(RASM) $(SRCDIR)/main.asm -I$(SRCDIR) -I$(BUILD) -ob $(BIN) -os $(SYM) -s

$(ARTBIN): $(SRCDIR)/art.asm $(BUILD)/creatures.raw $(BUILD)/sin.raw \
           $(BUILD)/font.raw $(BUILD)/scenofs.raw $(SND_OUT) Makefile
	@mkdir -p $(BUILD)
	$(RASM) $(SRCDIR)/art.asm -I$(SRCDIR) -I$(BUILD) -ob $(ARTBIN) -os $(ARTSYM)

# ---- sounds: one editable text file in, a step sequence out ----------------
sounds: $(SND_OUT)

$(BUILD)/sounds.raw $(BUILD)/sound_defs.inc: $(SOUNDTXT) tools/sounds.py
	@mkdir -p $(BUILD)
	python3 tools/sounds.py compile $(SOUNDTXT) $(BUILD)/

$(BUILD)/music.raw $(BUILD)/music_defs.inc: $(MUSICTXT) tools/music.py
	@mkdir -p $(BUILD)
	python3 tools/music.py compile $(MUSICTXT) $(BUILD)/

#  The round trip, same as the sheets and the levels: what shipped,
#  back as text you can edit.
sounds-export: $(BUILD)/sounds.raw $(BUILD)/music.raw
	python3 tools/sounds.py export $(BUILD)/sounds.raw $(BUILD)/sounds-export.txt
	python3 tools/music.py  export $(BUILD)/music.raw  $(BUILD)/music-export.txt

# ---- BASIC bootloader ------------------------------------------------------
$(LOADER): tools/make_loader.sh
	@mkdir -p $(BUILD)
	sh tools/make_loader.sh $(LOADER)

# ---- disk image ------------------------------------------------------------
dsk: $(DSK)

# ---- splash screen (uppercase copy so iDSK catalogues it as REVIVE8B.SCR) --
$(SPLASH): assets/revive8b.scr
	@mkdir -p $(BUILD)
	cp assets/revive8b.scr $(SPLASH)

#  SCORES.BIN goes on FIRST, and that ordering is the whole trick: its
#  data block deterministically lands on track 0 sector #C5, the first
#  data sector after the directory, which is the sector src/disk.asm
#  writes to by hand. The file is never opened at runtime — AMSDOS is
#  paged out — it exists only so the directory reserves that sector.
$(SCORES):
	@mkdir -p $(BUILD)
	{ printf 'FF'; head -c 510 /dev/zero; } > $(SCORES)

$(DSK): $(BIN) $(ARTBIN) $(LOADER) $(SPLASH) $(SCORES)
	@mkdir -p $(DIST)
	rm -f $(DSK)
	$(IDSK) $(DSK) -n -i $(SCORES) -t 0 -f
	$(IDSK) $(DSK) -i $(BIN) -t 1 -c $(LOAD_ADDR) -e $(EXEC_ADDR) -f
	$(IDSK) $(DSK) -i $(ARTBIN) -t 1 -c $(ART_ADDR) -e $(ART_ADDR) -f
	$(IDSK) $(DSK) -i $(SPLASH) -t 1 -c $(ART_ADDR) -f
	$(IDSK) $(DSK) -i $(LOADER) -t 0 -f
	@echo "--- catalogue of $(DSK) ---"
	$(IDSK) $(DSK) -l
	$(PYTHON) tools/dsk2ext.py $(DSK)

# ---- the two things the assembler cannot check -----------------------------
check-state:
	$(PYTHON) tools/checkstate.py

# ---- the paperwork ---------------------------------------------------------
#  docs/ holds both the sources and the built PDFs, and that is deliberate:
#  dist/ is in .gitignore, so a manual rendered into it does not survive a
#  clone. The two people who will ever read this want the PDF, not the
#  toolchain that makes it.
#
#  The renderer understands exactly the Markdown these two files use and
#  writes anything else out as it stands, so a construct it has never met
#  shows up in the PDF rather than vanishing from it.
DOCS      := docs
MANUALS   := $(DOCS)/manual.pdf $(DOCS)/manual-el.pdf
COVERS    := $(DOCS)/cover.png $(DOCS)/cover.pdf $(DOCS)/disc-label.png

docs: manual cover

manual: $(MANUALS)

#  Each manual opens on the sleeve, so the PDFs wait for the art.
$(DOCS)/manual.pdf: $(DOCS)/manual.md tools/mkmanual.py $(DOCS)/cover.png
	$(PYTHON) tools/mkmanual.py $< $@ $(DOCS)/cover.png

$(DOCS)/manual-el.pdf: $(DOCS)/manual-el.md tools/mkmanual.py $(DOCS)/cover.png
	$(PYTHON) tools/mkmanual.py $< $@ $(DOCS)/cover.png

# ---- sleeve art ------------------------------------------------------------
cover: $(COVERS)

$(DOCS)/cover.png: tools/mkcover.py
	$(PYTHON) tools/mkcover.py $(DOCS)

#  One run writes all three; these two only have to wait for it.
$(DOCS)/cover.pdf $(DOCS)/disc-label.png: $(DOCS)/cover.png
	@:

# ---- emulator --------------------------------------------------------------
run: dsk
	$(RVM) -b=cpc6128 -i "$(abspath $(DSK))" -c='RUN"FOWLS"\n' >/dev/null 2>&1 &

clean:
	rm -rf $(BUILD) $(DIST)
