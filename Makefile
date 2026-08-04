.PHONY: test docs

test:
	./tests/run.sh

docs:
	./tools/capture-screens.sh
