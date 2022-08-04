OUT=$(realpath .)/generated
SRC=$(realpath src)
SRCS=$(wildcard $(SRC)/*.tex)
OUTS=$(patsubst $(SRC)/%.tex,$(OUT)/%.pdf,$(SRCS))
OUTS:=$(subst .tex,.pdf,$(OUTS))


all: pdfs

pdfs: mkoutput $(OUTS)
	cd $(OUT) && rm *.log *.aux *.xtr 2>/dev/null; true

mkoutput:
	mkdir -p $(OUT)

$(OUT)/%.pdf: $(SRC)/%.tex
	cd $(OUT) && TEXINPUTS=$(SRC):$(TEXINPUTS) lualatex -shell-escape --interaction=batchmode $<

bib:
	wget https://wg21.link/index.bib -O $(SRC)/wg21.bib

clean:
	rm -r $(OUT)
