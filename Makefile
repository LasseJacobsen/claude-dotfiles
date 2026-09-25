.PHONY: install test check

install:
	bash install.sh

test:
	bash tests/test_hooks.sh
	bash tests/test_skills.sh
	bash tests/test_install.sh

check: test
