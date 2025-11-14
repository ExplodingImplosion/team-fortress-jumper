# You may run this script with:
# godot --script --headless .github/workflows/test_script.gd
extends SceneTree

func _init():
    var cfg = ConfigFile.new()
    cfg.load("export_presets.cfg")

    var export_presets = []
    for section in cfg.get_sections():
        if section.ends_with("options"):
            continue # No need, plus would lead to duplicates.

        export_presets.append({
            "name": cfg.get_value(section, "name"),
            "export_path": cfg.get_value(section, "export_path"),
            "filename": cfg.get_value(section, "export_path").get_file(),
        })

    print(export_presets)
    quit()