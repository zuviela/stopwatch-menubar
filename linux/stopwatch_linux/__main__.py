"""Entry point — `python3 -m stopwatch_linux`."""
from .app import StopwatchApp


def main() -> None:
    StopwatchApp().run()


if __name__ == "__main__":
    main()
