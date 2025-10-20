## Installation

```bash
zig build -Doptimize=ReleaseFast --prefix ~/.local
fish_add_path ~/.local/bin
```

## Usage
```bash
tiling_drag disable

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
