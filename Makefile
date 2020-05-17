OUT=$(realpath out)
SRC=$(realpath src)
SRCS=$(wildcard $(SRC)/*.tex)
OUTS=$(patsubst $(SRC)/%.tex,$(OUT)/%.pdf,$(SRCS))
OUTS:=$(subst .tex,.pdf,$(OUTS))


$(OUT)/%.pdf: $(SRC)/%.tex
	cd $(OUT) && TEXINPUTS=$(SRC):$(SRC)/../emojis:$(TEXINPUTS) lualatex -shell-escape --interaction=batchmode $<

.mkoutput:
	mkdir -p $(OUT)

pdfs: $(OUTS)
	cd $(OUT) && rm *.log *.aux *.xtr 2>/dev/null; true

all: pdfs

clean:
	rm -rf $(OUT)/*