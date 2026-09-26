from pathlib import Path

this_file = Path(__file__)

print(this_file)

parent = this_file.parent
grandparent = parent.parent

print(this_file)
print()
print(parent)
print(parent / "wezterm-run.lua")

print("wezterm-run.lua")
print("  wezterm-run.lua")
print("  Cargo.toml")
print("Cargo.toml")
print(grandparent)
print("File \"/foo/bar.py\", line 42")
print(parent / "wezterm-run.lua(34,56)")
print(parent / "wezterm-run.lua:3,56")
print(parent / "wezterm-run.lua:3:56")
print(parent / "wezterm-run.lua:309")
print(parent / "wezterm-run.lua(34,56)")
print(parent / "wezterm-run.lua(56)")
print(parent / "wezterm-run.lua")