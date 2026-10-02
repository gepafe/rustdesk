// Failover automatico a los servidores publicos de RustDesk (salvavidas):
// si la VPS propia deja de contestar, el cliente pasa solo a los servidores
// publicos y, cuando la VPS vuelve, restaura los valores propios.

use std::net::{SocketAddr, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use hbb_common::{
    config::{Config, LocalConfig},
    log,
};

// hbbs (registro) y hbbr (relay): los dos servicios que el cliente necesita.
const PROBES: &[&str] = &["147.15.111.14:21116", "147.15.111.14:21117"];
const PROBE_SECS: u64 = 30;
const FAILS_TO_PUBLIC: u32 = 3; // ~90 s de caida seguida
const OKS_TO_VPS: u32 = 2; // ~60 s de respuesta seguida

const K_ACTIVE: &str = "vps-failover";
const K_SAVED_CUSTOM: &str = "vps-failover-custom";
const K_SAVED_RELAY: &str = "vps-failover-relay";
const K_SAVED_KEY: &str = "vps-failover-key";

// Datos de la VPS embebidos para que una PC nueva conecte sin carga manual.
const EMBED_CUSTOM: &str = "147.15.111.14";
const EMBED_RELAY: &str = "147.15.111.14:21117";
const EMBED_KEY: &str = "ehPisWWzu71QSwcOHSyYDFyZPysdul8zk1hebPpDW68=";
const K_EMBEDDED: &str = "vps-embedded";

fn probe_ok() -> bool {
    PROBES.iter().all(|p| {
        p.parse::<SocketAddr>()
            .map(|sa| TcpStream::connect_timeout(&sa, Duration::from_secs(3)).is_ok())
            .unwrap_or(false)
    })
}

fn apply(custom: &str, relay: &str, key: &str) {
    Config::set_option("custom-rendezvous-server".to_owned(), custom.to_owned());
    Config::set_option("relay-server".to_owned(), relay.to_owned());
    Config::set_option("key".to_owned(), key.to_owned());
    crate::rendezvous_mediator::RendezvousMediator::restart();
}

fn go_public() {
    // Respalda los valores vigentes (los de la VPS) antes de tocarlos.
    LocalConfig::set_option(
        K_SAVED_CUSTOM.to_owned(),
        Config::get_option("custom-rendezvous-server"),
    );
    LocalConfig::set_option(
        K_SAVED_RELAY.to_owned(),
        Config::get_option("relay-server"),
    );
    LocalConfig::set_option(K_SAVED_KEY.to_owned(), Config::get_option("key"));
    LocalConfig::set_option(K_ACTIVE.to_owned(), "Y".to_owned());
    // Opciones vacias => get_rendezvous_servers() cae en la lista publica.
    apply("", "", "");
    log::warn!("failover: la VPS no responde, se pasa a los servidores publicos");
}

fn go_vps() {
    let custom = LocalConfig::get_option(K_SAVED_CUSTOM);
    if custom.is_empty() {
        // Sin valores guardados no hay a que volver.
        LocalConfig::set_option(K_ACTIVE.to_owned(), String::new());
        return;
    }
    let relay = LocalConfig::get_option(K_SAVED_RELAY);
    let key = LocalConfig::get_option(K_SAVED_KEY);
    apply(&custom, &relay, &key);
    LocalConfig::set_option(K_ACTIVE.to_owned(), String::new());
    log::warn!("failover: la VPS volvio, se restaura el servidor propio");
}

// Se ejecuta una sola vez por equipo (primer arrancada). Solo rellena si no hay
// servidor configurado y no hay failover activo: vacio + failover significa que
// la VPS esta caida, no que falte configurar, y tras pedir datos a mano o
// borrarlos a proposito nunca vuelve a tocar nada.
pub fn ensure_embedded() {
    if LocalConfig::get_option(K_EMBEDDED) == "Y" {
        return;
    }
    if LocalConfig::get_option(K_ACTIVE) != "Y"
        && Config::get_option("custom-rendezvous-server").is_empty()
    {
        Config::set_option("custom-rendezvous-server".to_owned(), EMBED_CUSTOM.to_owned());
        Config::set_option("relay-server".to_owned(), EMBED_RELAY.to_owned());
        Config::set_option("key".to_owned(), EMBED_KEY.to_owned());
        log::info!("config: servidor VPS embebido en la primera arrancada");
    }
    LocalConfig::set_option(K_EMBEDDED.to_owned(), "Y".to_owned());
}

fn monitor_loop() {
    let mut fails: u32 = 0;
    let mut oks: u32 = 0;
    loop {
        std::thread::sleep(Duration::from_secs(PROBE_SECS));
        let ok = probe_ok();
        if LocalConfig::get_option(K_ACTIVE) == "Y" {
            // En failover solo se vigila la vuelta a la VPS; si el usuario
            // repunta la VPS a mano mientras esta caida, se respeta.
            if ok {
                oks += 1;
                if oks >= OKS_TO_VPS {
                    go_vps();
                    fails = 0;
                    oks = 0;
                }
            } else {
                oks = 0;
            }
        } else if !ok && !Config::get_option("custom-rendezvous-server").is_empty() {
            fails += 1;
            if fails >= FAILS_TO_PUBLIC {
                go_public();
                fails = 0;
            }
        } else {
            fails = 0;
        }
    }
}

pub fn spawn_failover_monitor() {
    static STARTED: AtomicBool = AtomicBool::new(false);
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(monitor_loop);
}
