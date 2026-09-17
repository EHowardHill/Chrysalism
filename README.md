# Chrysalism

*n. the amniotic tranquility of being indoors during a thunderstorm* —
[The Dictionary of Obscure Sorrows](https://www.dictionaryofobscuresorrows.com)

Chrysalism is a lightweight menu bar utility that simulates rain behind your icons and windows.

Created because of the unstable leadership situation surrounding [lo-rain](https://lo-rain.com).

## Requirements

- macOS 13 or later
- Xcode command line tools (to build)

## Build & run

```sh
make run        # builds Chrysalism.app and opens it
```

or manually:

```sh
swift build -c release
make app
open Chrysalism.app
```

and then to install:

```sh
make install      # builds Chrysalism.app and copies it to ~/Applications
```

## Releasing

To produce the artifact for a GitHub release page:

```sh
make release      # builds Chrysalism.app and zips it to Chrysalism-macOS.zip
```

To generate the app icon:

```sh
make icon
```

## Menu

Click the raindrop in your menu bar:

| Item | Description |
| --- | --- |
| **Rain** | Turn the rain on or off |
| **Intensity** | Drizzle / Light / Steady / Downpour |
| **Slant** | Drag the slider to set the rainfall's angle (−45° to 45°) |
| **Rain Bounces Off Dock** | Toggle — drops land on the Dock panel and bounce (the display hosting the Dock) |
| **Show Rain On** | Pick which refresh-rate-matched display set gets rain (only shown when displays differ) |
| **Launch at Login** | Start Chrysalism automatically when you log in |

## License

MIT — see [LICENSE](LICENSE).