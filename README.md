## Installation

```console
❯ zig build -Doptimize=ReleaseFast --prefix ~/.local
❯ fish_add_path ~/.local/bin
```

## Usage
```console
❯ swaycolumns --help
Usage: swaycolumns [command] [parameter]

  start [modifier]    Start the daemon and set a floating modifier.
  move <direction>    Move windows or swap columns.
  focus <target>      Focus window, column or workspace.
  layout <mode>       Switch column layout to splitv or stacking.

  -h, --help          Print this message and quit.
```

```
default_orientation horizontal

bindsym {
    super+shift+right exec swaycolumns move right
    super+shift+left  exec swaycolumns move left
    super+shift+up    exec swaycolumns move up
    super+shift+down  exec swaycolumns move down

    super+v exec swaycolumns focus  toggle
    super+b exec swaycolumns layout toggle
}

exec {
    swaycolumns start
}
```

## Dog
<img src="dog.jpg" alt="dog" width="400"/>
