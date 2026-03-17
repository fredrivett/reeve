.PHONY: build run clean

build:
	swift build -c release

run:
	swift run Reeve

clean:
	swift package clean
