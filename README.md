## Installation

```console
❯ zig build -Doptimize=ReleaseFast --prefix ~/.local
❯ fish_add_path ~/.local/bin
```

## Usage
```console
❯ swaycolumns --help
Usage: swaycolumns [command] [parameter]

  start [modifier]                  Start the background process and set a floating modifier.
  move <direction>                  Move windows or swap columns.
  move workspace [number] <name>    Move window or column to workspace.
  focus <target>                    Focus window, column or workspace.
  layout <mode>                     Switch column layout to splitv or stacking.

  -h, --help                        Print this message and quit.
```

```
default_orientation  horizontal
focus_follows_mouse  always
tiling_drag          disable
floating_modifier    super normal

bindsym {
    super+shift+right  exec swaycolumns move right
    super+shift+left   exec swaycolumns move left
    super+shift+up     exec swaycolumns move up
    super+shift+down   exec swaycolumns move down

    super+shift+1  exec swaycolumns move workspace number 1
    super+shift+2  exec swaycolumns move workspace number 2
    super+shift+3  exec swaycolumns move workspace number 3
    super+shift+4  exec swaycolumns move workspace number 4
    super+shift+5  exec swaycolumns move workspace number 5
    super+shift+6  exec swaycolumns move workspace number 6
    super+shift+7  exec swaycolumns move workspace number 7
    super+shift+8  exec swaycolumns move workspace number 8
    super+shift+9  exec swaycolumns move workspace number 9
    super+shift+0  exec swaycolumns move workspace number 10

    super+v  exec swaycolumns focus  toggle
    super+b  exec swaycolumns layout toggle
}

exec {
    swaycolumns start super
}
```

## Dog
<img src="dog.jpg" alt="dog" width="400"/>
