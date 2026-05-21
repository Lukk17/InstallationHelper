# Mouse Move

> Tiny Windows batch script that nudges the mouse pointer to keep a session awake.

---

### What it is

---

A single `.bat` file that ships with this repo for convenience. The implementation is a fork of
[npocmaka/batch.scripts mouse.bat](https://github.com/npocmaka/batch.scripts/blob/master/hybrids/.net/c/mouse.bat),
unchanged from upstream.

Use it on Windows when you want to keep a remote desktop session, screen lock timer, or presence indicator from going
idle without installing a heavier tool.

### How to run it

---

Double-click the `.bat` file or run from PowerShell:

```powershell
.\mouse.bat
```

`Ctrl+C` stops it.

### Credit

---

All credit goes to [npocmaka](https://github.com/npocmaka) for the original C-in-batch hybrid trick. This README and
its placement in [utils/mouseMove/](.) is the only thing added.
