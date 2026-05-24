use std::io::Write;

use anyhow::{Context, Result, anyhow};
use nusb::descriptors::TransferType;
use nusb::transfer::{Bulk, Direction, In, Out};
use nusb::{DeviceInfo, Interface, MaybeFuture};

const USB_CLASS_PRINTER: u8 = 0x07;

/// USB IEEE 1284 printer-class transport.
///
/// `open()` finds the device by VID:PID, claims its printer-class interface,
/// and remembers the bulk OUT endpoint to write print data to.
pub struct UsbPrinter {
    interface: Interface,
    info: PrinterInfo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PrinterId {
    pub vid: u16,
    pub pid: u16,
}

#[derive(Debug, Clone)]
pub struct PrinterInfo {
    pub manufacturer: Option<String>,
    pub product: Option<String>,
    pub serial: Option<String>,
    pub vid: u16,
    pub pid: u16,
    pub interface_number: u8,
    pub bulk_out: u8,
    pub bulk_in: Option<u8>,
}

impl UsbPrinter {
    pub fn open(id: PrinterId) -> Result<Self> {
        let dev_info = find_device(id)?;
        let manufacturer = dev_info.manufacturer_string().map(str::to_owned);
        let product = dev_info.product_string().map(str::to_owned);
        let serial = dev_info.serial_number().map(str::to_owned);

        let device = dev_info.open().wait().context("opening USB device")?;
        let cfg = device
            .active_configuration()
            .context("reading active configuration")?;

        let mut found: Option<(u8, u8, Option<u8>)> = None;
        for iface in cfg.interfaces() {
            let Some(alt) = iface.alt_settings().next() else { continue };
            if alt.class() != USB_CLASS_PRINTER {
                continue;
            }
            let mut bulk_out = None;
            let mut bulk_in = None;
            for ep in alt.endpoints() {
                if ep.transfer_type() != TransferType::Bulk {
                    continue;
                }
                match ep.direction() {
                    Direction::Out => bulk_out = Some(ep.address()),
                    Direction::In => bulk_in = Some(ep.address()),
                }
            }
            if let Some(out) = bulk_out {
                found = Some((alt.interface_number(), out, bulk_in));
                break;
            }
        }

        let (iface_num, bulk_out, bulk_in) = found.ok_or_else(|| {
            anyhow!(
                "device {:04x}:{:04x} exposes no USB Printer Class interface with a bulk OUT endpoint",
                id.vid, id.pid
            )
        })?;

        let interface = device
            .claim_interface(iface_num)
            .wait()
            .with_context(|| format!("claiming interface {iface_num}"))?;

        let info = PrinterInfo {
            manufacturer,
            product,
            serial,
            vid: id.vid,
            pid: id.pid,
            interface_number: iface_num,
            bulk_out,
            bulk_in,
        };

        Ok(UsbPrinter { interface, info })
    }

    pub fn info(&self) -> &PrinterInfo {
        &self.info
    }
    pub fn bulk_out(&self) -> u8 {
        self.info.bulk_out
    }
    pub fn bulk_in(&self) -> Option<u8> {
        self.info.bulk_in
    }

    /// Send a complete print job (already in the printer's native protocol) to
    /// the bulk OUT endpoint. Uses nusb's `EndpointWrite` which implements
    /// `std::io::Write` and handles transfer queueing internally.
    pub fn write_job(&self, data: &[u8]) -> Result<()> {
        let endpoint = self
            .interface
            .endpoint::<Bulk, Out>(self.info.bulk_out)
            .context("claiming bulk OUT endpoint")?;
        let mut writer = endpoint.writer(256 * 1024);
        writer
            .write_all(data)
            .context("writing print data to bulk OUT")?;
        writer.flush().context("flushing bulk OUT")?;
        Ok(())
    }
}

fn find_device(id: PrinterId) -> Result<DeviceInfo> {
    nusb::list_devices()
        .wait()
        .context("enumerating USB devices")?
        .find(|d| d.vendor_id() == id.vid && d.product_id() == id.pid)
        .ok_or_else(|| anyhow!("device {:04x}:{:04x} not found on USB bus", id.vid, id.pid))
}

/// Diagnostic helper: list every USB device and dump descriptors for any printer-class device.
pub fn probe_all() -> Result<()> {
    let devices: Vec<_> = nusb::list_devices()
        .wait()
        .context("enumerating USB devices")?
        .collect();
    println!("USB devices visible to nusb: {}\n", devices.len());
    for d in &devices {
        println!(
            "  {:04x}:{:04x}  {} / {}",
            d.vendor_id(),
            d.product_id(),
            d.manufacturer_string().unwrap_or("<no mfg>"),
            d.product_string().unwrap_or("<no product>"),
        );
    }
    println!();

    for d in &devices {
        let Ok(dev) = d.open().wait() else { continue };
        let Ok(cfg) = dev.active_configuration() else { continue };
        let is_printer = cfg.interfaces().any(|iface| {
            iface
                .alt_settings()
                .any(|alt| alt.class() == USB_CLASS_PRINTER)
        });
        if !is_printer {
            continue;
        }
        println!(
            "{:04x}:{:04x}  {}",
            d.vendor_id(),
            d.product_id(),
            d.product_string().unwrap_or("<no product>")
        );
        for iface in cfg.interfaces() {
            for alt in iface.alt_settings() {
                let marker = if alt.class() == USB_CLASS_PRINTER {
                    "  <-- USB PRINTER CLASS"
                } else {
                    ""
                };
                println!(
                    "  Interface {} (alt {}): class=0x{:02x} sub=0x{:02x} proto=0x{:02x}{}",
                    alt.interface_number(),
                    alt.alternate_setting(),
                    alt.class(),
                    alt.subclass(),
                    alt.protocol(),
                    marker
                );
                for ep in alt.endpoints() {
                    let dir = match ep.direction() {
                        Direction::In => "IN ",
                        Direction::Out => "OUT",
                    };
                    println!(
                        "    Endpoint 0x{:02x} {}  {:?}  max_packet={}",
                        ep.address(),
                        dir,
                        ep.transfer_type(),
                        ep.max_packet_size()
                    );
                }
            }
        }
        println!();
    }
    Ok(())
}

// Silence unused import warning if In ever becomes unused above.
#[allow(dead_code)]
fn _phantom_in() -> Option<In> {
    None
}
