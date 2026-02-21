## Usage

* Automatic actions
    * First window in the workspace is opened as usual.
    * Second window will appear to the right of the first window.
    * All subsequent windows will appear below the currently focused one, creating a column.

* `swaycolumns move`
    * Use the parameters `up` and `down` to move the window within the column.
    * Use `left` and `right` to move the window between columns.
    * Moving a window in the direction of the screen edge creates a new column.

* `swaycolumns layout`
    * Use `toggle`, `splitv` or `stacking` to set the layout of the column.
    * This also works on floating windows.
    * Moving windows within and between columns works regardless of layout.

* `swaycolumns focus`
    * Use `toggle` `window`, `column` or `workspace` to set window, column and workspace focus.
    * This too works on floating windows.
    * If a column is focused, moving it will swap it with the neighbouring column.

* `swaycolumns move workspace`
    * Use it to move the window, column or everything to another workspace.
    * Moved windows will be inserted into columns while moved columns will appear on the right.
    * Workspace selection is prevented from being moved to a non-empty workspace.

* Optional floating modifier
    * Specify the modifer in order to use a simplified window dragging mechanic.
    * Hold the modifier and drag with LMB over two windows within the same column to swap them.
    * Drag over two windows in diffrent columns to move the first window into the second column.

## Configuration

 Including these options and keybinds is highly recommended. Invocations of `swaycolumns` should be preferred over commands provided by Sway in order to avoid unexpected behaviour.

```
default_orientation  horizontal
focus_follows_mouse  always
tiling_drag          disable
floating_modifier    super normal

bindsym --no-repeat {
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

## CLI

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

## Installation

```console
❯ zig build -Doptimize=ReleaseFast --prefix ~/.local
❯ export PATH=$PATH:~/.local/bin
```
