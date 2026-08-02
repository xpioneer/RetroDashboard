.PHONY: run clean build release

run:
	swift run

clean:
	rm -rf .build

# Debug编译
build:
	swift build

# 正式Release编译
release:
	swift build -c release