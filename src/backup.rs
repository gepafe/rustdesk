use std::{fs, thread, time::Duration};

use hbb_common::{config::Config, log, ResultType};

fn config_dir() -> Option<std::path::PathBuf> {
    Config::path("RustDesk.toml")
        .parent()
        .map(|p| p.to_path_buf())
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
    let mut files = serde_json::Map::new();
    for entry in fs::read_dir(&dir)? {
        let path = entry?.path();
        if !path.is_file() {
            continue;
        }
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            let data = fs::read(&path)?;
            files.insert(
                name.to_owned(),
                serde_json::Value::String(crate::common::encode64(data)),
            );
        }
    }
    let data = serde_json::json!({
        "version": 1,
        "files": files,
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
        if name.is_empty() || name.starts_with('.') || name.contains('/') || name.contains('\\') {
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
        fs::write(dir.join(name.as_str()), bytes)?;
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
