clean:
	rm -rf build

build:
	./build.sh

install: clean
	./install.sh

kill:
	pkill -9 -f "OptWin" || echo "No running OptWin processes found."

run: kill clean
	./install.sh --run
