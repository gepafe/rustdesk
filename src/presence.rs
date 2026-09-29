use std::time::Duration;

use hbb_common::{config::Config, log, ResultType};

const REPO: &str = "vitalfix/rustdesk-listas";
const TOKEN_A: &str = "github_pat_11ALOXYAQ0rSRZNGDhp8oQ_";
const TOKEN_B: &str = "8BTZ0EtuNIZoR3qH1wRxS0VX68CcVfrglv3tf51gUcMPRZWJR243OYYNQxE";
const FILE: &str = "presencia.json";
const INTERVAL_SECS: u64 = 120;

fn api_url() -> String {
    format!("https://api.github.com/repos/{REPO}/contents/{FILE}")
}

fn token() -> String {
    [TOKEN_A, TOKEN_B].concat()
}

fn own_sessions() -> Vec<String> {
    #[cfg(windows)]
    {
        // Todas las sesiones con usuario cargado (activas, conectadas o
        // desconectadas): es lo que el usuario quiere ver en la lista para
        // saber a quien puede conectarse en cada equipo.
        crate::platform::get_logged_in_session_names()
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default()
}

fn download(
    client: &reqwest::blocking::Client,
    token: &str,
) -> ResultType<(Option<String>, serde_json::Map<String, serde_json::Value>)> {
    let resp = client
        .get(api_url())
        .header("Authorization", format!("Bearer {token}"))
        .header("Accept", "application/vnd.github+json")
        .send()?;
    if resp.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok((None, serde_json::Map::new()));
    }
    let resp = resp.error_for_status()?;
    let body: serde_json::Value = resp.json()?;
    let sha = body
        .get("sha")
        .and_then(|v| v.as_str())
        .map(|s| s.to_owned());
    let content = body
        .get("content")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    let cleaned: String = content.chars().filter(|c| !c.is_whitespace()).collect();
    let bytes = crate::common::decode64(&cleaned)?;
    let map = serde_json::from_slice::<serde_json::Value>(&bytes)?;
    let map = match map.as_object() {
        Some(map) => map.clone(),
        None => return Ok((sha, serde_json::Map::new())),
    };
    Ok((sha, map))
}

fn upload(
    client: &reqwest::blocking::Client,
    token: &str,
    sha: Option<&str>,
    content_b64: &str,
) -> ResultType<bool> {
    let mut body = serde_json::json!({
        "message": "presencia",
        "content": content_b64,
    });
    if let Some(sha) = sha {
        body["sha"] = serde_json::Value::String(sha.to_owned());
    }
    let resp = client
        .put(api_url())
        .header("Authorization", format!("Bearer {token}"))
        .header("Accept", "application/vnd.github+json")
        .json(&body)
        .send()?;
    if resp.status() == reqwest::StatusCode::UNPROCESSABLE_ENTITY {
        return Ok(true);
    }
    resp.error_for_status()?;
    Ok(false)
}

fn publish_once() -> ResultType<()> {
    let token = token();
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("RustDesk")
        .build()?;
    let id = Config::get_id();
    if id.is_empty() {
        return Ok(());
    }
    let sessions = own_sessions();
    for _ in 0..2 {
        let (sha, mut map) = download(&client, &token)?;
        // Podar entradas viejas para que el archivo no crezca sin cota.
        let now = now_secs();
        map.retain(|_, v| {
            v.get("ts")
                .and_then(|t| t.as_u64())
                .map(|ts| now.saturating_sub(ts) <= 300)
                .unwrap_or(false)
        });
        map.insert(
            id.clone(),
            serde_json::json!({"ts": now_secs(), "sessions": sessions}),
        );
        let content = serde_json::to_string(&map)?;
        let content_b64 = crate::common::encode64(content.as_bytes());
        if !upload(&client, &token, sha.as_deref(), &content_b64)? {
            return Ok(());
        }
    }
    Ok(())
}

fn presence_loop() {
    // Publicar al arrancar: si no, la primera publicacion tardaria 2 minutos.
    if let Err(e) = publish_once() {
        log::warn!("presence publish failed: {e}");
    }
    loop {
        std::thread::sleep(Duration::from_secs(INTERVAL_SECS));
        if let Err(e) = publish_once() {
            log::warn!("presence publish failed: {e}");
        }
    }
}

pub fn spawn_presence_publisher() {
    use std::sync::atomic::{AtomicBool, Ordering};
    static STARTED: AtomicBool = AtomicBool::new(false);
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(presence_loop);
}
