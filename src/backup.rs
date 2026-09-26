use std::{fs, path::Path, path::PathBuf, thread, time::Duration};

use hbb_common::{config::Config, log, ResultType};

fn config_dir() -> Option<PathBuf> {
    Config::path("RustDesk.toml")
        .parent()
        .map(|p| p.to_path_buf())
}

fn collect_files(dir: &Path, base: &Path, out: &mut Vec<(String, PathBuf)>) {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = match path
            .strip_prefix(base)
            .ok()
            .and_then(|p| p.to_str())
        {
            Some(name) => name.replace('\\', "/"),
            None => continue,
        };
        if path.is_dir() {
            collect_files(&path, base, out);
        } else if path.is_file() {
            out.push((name, path));
        }
    }
}

/// Exporta toda la configuracion local (equipos, carpetas, opciones y claves) como texto.
pub fn export() -> String {
    match do_export() {
        Ok(data) => data,
        Err(e) => {
            log::error!("export backup failed: {}", e);
            Default::default()
        }
    }
}

fn do_export() -> ResultType<String> {
    let dir = match config_dir() {
        Some(dir) => dir,
        None => return Ok(Default::default()),
    };
    let mut entries = Vec::new();
    collect_files(&dir, &dir, &mut entries);
    let mut files = serde_json::Map::new();
    let mut mtimes = serde_json::Map::new();
    for (name, path) in entries {
        let data = fs::read(&path)?;
        let modified = fs::metadata(&path)
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs());
        files.insert(
            name.clone(),
            serde_json::Value::String(crate::common::encode64(data)),
        );
        if let Some(secs) = modified {
            mtimes.insert(name, serde_json::json!(secs));
        }
    }
    let data = serde_json::json!({
        "version": 3,
        "files": files,
        "mtimes": mtimes,
    });
    Ok(data.to_string())
}

/// Restaura un respaldo generado por [export]. Devuelve cuantos archivos restauro.
pub fn import(data: &str) -> i32 {
    match do_import(data) {
        Ok(n) => n,
        Err(e) => {
            log::error!("import backup failed: {}", e);
            0
        }
    }
}

fn valid_name(name: &str) -> bool {
    if name.is_empty() || name.starts_with('/') || name.starts_with('\\') || name.contains(':') {
        return false;
    }
    name.split('/')
        .all(|part| !part.is_empty() && part != "." && part != "..")
}

fn do_import(data: &str) -> ResultType<i32> {
    let value: serde_json::Value = serde_json::from_str(data)?;
    let files = match value.get("files").and_then(|f| f.as_object()) {
        Some(files) => files,
        None => return Ok(0),
    };
    let dir = match config_dir() {
        Some(dir) => dir,
        None => return Ok(0),
    };
    let mut count = 0;
    for (name, value) in files {
        if !valid_name(name) {
            continue;
        }
        let content = match value.as_str() {
            Some(content) => content,
            None => continue,
        };
        let bytes = match crate::common::decode64(content) {
            Ok(bytes) => bytes,
            Err(e) => {
                log::error!("invalid backup file {name}: {e}");
                continue;
            }
        };
        let path = dir.join(name.as_str());
        if let Some(parent) = path.parent() {
            if let Err(e) = fs::create_dir_all(parent) {
                log::error!("cannot create {:?}: {}", parent, e);
                continue;
            }
        }
        fs::write(&path, bytes)?;
        count += 1;
    }
    Ok(count)
}

/// Cierra la app para que los datos restaurados se apliquen al volver a abrirla.
pub fn restart() {
    let _ = thread::spawn(|| {
        thread::sleep(Duration::from_millis(1500));
        std::process::exit(0);
    });
}
