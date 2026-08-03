# Configure instance alias for commodore component compile
commodore_args += --alias $(instance)

.PHONY: test-espejote
test-espejote:
	bash tests/render/run.sh
	git diff --exit-code -- tests/render/expected/

.PHONY: gen-espejote
gen-espejote:
	bash tests/render/run.sh
