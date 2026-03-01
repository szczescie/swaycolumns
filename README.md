## Usage

* Automatic actions
    * Second window will appear to the right of the first window.
    * All subsequent windows will appear below the currently focused one, creating a column.

* `swaycolumns move`
    * Use the parameters `up` and `down` to move the window within the column.
    * Use `left` and `right` to move the window between columns or create new ones.

* `swaycolumns move workspace`
    * Use it to move the window, column or everything to another workspace.
    * Workspace selection is prevented from being moved to a non-empty workspace.

* `swaycolumns focus`
    * Use `toggle` `window`, `column` or `workspace` to set window, column and workspace focus.
    * If a column is focused, moving it will swap it with the neighbouring column.

* `swaycolumns layout`
    * Use `toggle`, `splitv` or `stacking` to set the layout of the column.
    * This also works on floating windows.

* `swaycolumns floating`
    * Use `toggle`, `enable` or `disable` to change the floating state.
    * Workspaces and non-stacked columns are prevented from floating.

* Optional floating modifier
    * Specify the modifer in order to use a simplified window dragging mechanic.
    * Windows can be moved within columns or swapped between them without precise movements.

## Configuration

Including these options and commands is recommended. Invocations of `swaycolumns` should be preferred over commands provided by Sway in order to avoid unexpected behaviour. 

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

    super+c  exec swaycolumns floating toggle
    super+v  exec swaycolumns focus toggle
    super+b  exec swaycolumns layout toggle
}

exec {
    swaycolumns start super
}
```

## CLI

```console
❯ swaycolumns --help
Usage: swaycolumns [option] <command>

Commands:

  start                             Start the process without affecting window dragging
  start <modifier>                  Start the background process and set a floating modifier
  move <direction>                  Move windows or swap columns
  move workspace <name>             Move a window or column to a named workspace
  move workspace number <number>    Move a window or column to an indexed workspace
  focus <target>                    Focus a window, column or workspace
  layout <mode>                     Switch the column layout to splitv or stacking
  floating <state>                  Switch the window or stacked column's floating state

Options:

  -m, --memory <bytes>              Amount of bytes allocated at startup (default: 1048576)
  -h, --help                        Print this message and exit
```

## Installation

```console
❯ zig build -Doptimize=ReleaseFast --prefix ~/.local
❯ export PATH=$PATH:~/.local/bin
```
