use std::fs;
use std::io::{self, BufReader, Read};
use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};

use printer_studio::encoders::{Duplex, JobOptions, PaperSize, find_encoder_for};
use printer_studio::raster::{MonoPage, pattern, pwg};
use printer_studio::usb::{PrinterId, UsbPrinter, probe_all};

#[derive(Parser)]
#[command(
    name = "printer-studio",
    version,
    about = "USB printer engine for Samsung-engine HP Laser printers"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Enumerate USB devices and dump descriptors for any printer-class device.
    Probe,

    /// Show identification info for one printer-class device by VID:PID.
    Info {
        #[arg(long, value_parser = parse_hex_u16, default_value = "0x03F0")]
        vid: u16,
        #[arg(long, value_parser = parse_hex_u16, default_value = "0xE82A")]
        pid: u16,
    },

    /// Encode a built-in test pattern as QPDL and save it to a file (DOES NOT PRINT).
    EncodeTestPage {
        /// Output file path for the encoded QPDL byte stream.
        #[arg(short, long)]
        out: PathBuf,
        /// Print resolution in DPI.
        #[arg(long, default_value_t = 600)]
        dpi: u32,
        /// Paper size (letter, a4, legal).
        #[arg(long, default_value = "letter")]
        paper: String,
    },

    /// Read a PWG-Raster job from stdin (or file), encode it for the
    /// printer, and either save it to a file or transmit it via USB.
    ///
    /// This is the entry point called by `ippeveprinter -c ...` when an
    /// AirPrint job arrives. Defaults to `--dry-run` (save to file) until
    /// the QPDL encoder is fully validated; pass `--i-know-what-im-doing`
    /// to actually transmit.
    PrintJob {
        /// Input file (PWG-Raster). If omitted, reads from stdin.
        input: Option<PathBuf>,

        /// Dump the encoded byte stream to this file instead of printing.
        /// When called from ippeveprinter, this is the natural debug mode.
        #[arg(long)]
        dry_run_out: Option<PathBuf>,

        /// VID/PID of the target printer (defaults to HP Laser 107a).
        #[arg(long, value_parser = parse_hex_u16, default_value = "0x03F0")]
        vid: u16,
        #[arg(long, value_parser = parse_hex_u16, default_value = "0xE82A")]
        pid: u16,

        /// Send to the physical printer. Required to transmit bytes;
        /// otherwise nothing is sent.
        #[arg(long)]
        i_know_what_im_doing: bool,
    },

    /// Send an already-encoded QPDL byte stream from FILE to the printer's
    /// bulk OUT endpoint. The lowest-level transmit command.
    SendRaw {
        file: PathBuf,
        #[arg(long, value_parser = parse_hex_u16, default_value = "0x03F0")]
        vid: u16,
        #[arg(long, value_parser = parse_hex_u16, default_value = "0xE82A")]
        pid: u16,
        /// Required: refuses to transmit without this flag.
        #[arg(long)]
        i_know_what_im_doing: bool,
    },
}

fn parse_hex_u16(s: &str) -> Result<u16, String> {
    let s = s.trim_start_matches("0x").trim_start_matches("0X");
    u16::from_str_radix(s, 16).map_err(|e| format!("invalid hex u16 {s:?}: {e}"))
}

fn parse_paper(s: &str) -> Result<PaperSize> {
    Ok(match s.to_ascii_lowercase().as_str() {
        "letter" => PaperSize::Letter,
        "a4" => PaperSize::A4,
        "legal" => PaperSize::Legal,
        other => bail!("unknown paper size {other:?}; expected letter, a4, legal"),
    })
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e:#}");
            ExitCode::FAILURE
        }
    }
}

fn run(cli: Cli) -> Result<()> {
    match cli.command {
        Command::Probe => probe_all(),
        Command::Info { vid, pid } => cmd_info(vid, pid),
        Command::EncodeTestPage { out, dpi, paper } => {
            cmd_encode_test(out, dpi, parse_paper(&paper)?)
        }
        Command::PrintJob {
            input,
            dry_run_out,
            vid,
            pid,
            i_know_what_im_doing,
        } => cmd_print_job(input, dry_run_out, vid, pid, i_know_what_im_doing),
        Command::SendRaw {
            file,
            vid,
            pid,
            i_know_what_im_doing,
        } => cmd_send_raw(file, vid, pid, i_know_what_im_doing),
    }
}

fn cmd_info(vid: u16, pid: u16) -> Result<()> {
    let printer = UsbPrinter::open(PrinterId { vid, pid })?;
    let i = printer.info();
    println!(
        "Manufacturer:   {}",
        i.manufacturer.as_deref().unwrap_or("<none>")
    );
    println!(
        "Product:        {}",
        i.product.as_deref().unwrap_or("<none>")
    );
    println!(
        "Serial:         {}",
        i.serial.as_deref().unwrap_or("<none>")
    );
    println!("VID:PID:        {:04x}:{:04x}", i.vid, i.pid);
    println!("Interface:      {}", i.interface_number);
    println!("Bulk OUT:       0x{:02x}", i.bulk_out);
    println!(
        "Bulk IN:        {}",
        i.bulk_in
            .map(|a| format!("0x{a:02x}"))
            .unwrap_or_else(|| "<none>".to_string())
    );
    let driver = find_encoder_for(vid, pid)
        .map(|e| e.name().to_string())
        .unwrap_or_else(|| "<no driver registered>".to_string());
    println!("Driver:         {driver}");
    Ok(())
}

fn cmd_encode_test(out: PathBuf, dpi: u32, paper: PaperSize) -> Result<()> {
    let (w, h) = paper.pixels(dpi);
    println!("Generating test page: {w}×{h} px at {dpi} DPI ({paper:?})");
    let page = pattern::test_page(w, h, dpi);
    encode_pages_to_file(&[page], paper, &out)
}

fn encode_pages_to_file(pages: &[MonoPage], paper: PaperSize, out: &PathBuf) -> Result<()> {
    let opts = JobOptions {
        copies: 1,
        paper,
        duplex: Duplex::None,
        job_name: "printer-studio job".into(),
        user_name: "printer-studio".into(),
    };

    let encoder = find_encoder_for(0x03F0, 0xE82A)
        .context("no encoder registered for default device (this is a bug)")?;

    let bytes = encoder.encode(pages, &opts)?;
    fs::write(out, &bytes).with_context(|| format!("writing {}", out.display()))?;
    println!("Wrote {} bytes to {}", bytes.len(), out.display());
    println!("Driver: {}", encoder.name());
    Ok(())
}

fn cmd_print_job(
    input: Option<PathBuf>,
    dry_run_out: Option<PathBuf>,
    vid: u16,
    pid: u16,
    confirmed: bool,
) -> Result<()> {
    // Read PWG-Raster from stdin or the given file path. ippeveprinter
    // hands us the document via stdin.
    eprintln!("printer-studio: reading PWG-Raster from {}", match &input {
        Some(p) => p.display().to_string(),
        None => "<stdin>".to_string(),
    });

    let pages = match input.as_ref() {
        Some(path) => {
            let f = fs::File::open(path).with_context(|| format!("opening {}", path.display()))?;
            pwg::read_all_pages(&mut BufReader::new(f))?
        }
        None => {
            let stdin = io::stdin();
            let mut locked: Box<dyn Read> = Box::new(BufReader::new(stdin.lock()));
            pwg::read_all_pages(&mut locked)?
        }
    };

    if pages.is_empty() {
        bail!("PWG-Raster stream had no pages");
    }
    eprintln!(
        "printer-studio: parsed {} page(s); first is {}×{} at {} DPI",
        pages.len(),
        pages[0].width_px,
        pages[0].height_px,
        pages[0].dpi
    );

    let opts = JobOptions {
        copies: 1,
        paper: PaperSize::Letter,
        duplex: Duplex::None,
        job_name: std::env::var("IPP_JOB_NAME").unwrap_or_else(|_| "ipp job".into()),
        user_name: std::env::var("IPP_REQUESTING_USER_NAME").unwrap_or_else(|_| "ipp".into()),
    };

    let encoder = find_encoder_for(vid, pid)
        .ok_or_else(|| anyhow::anyhow!("no encoder registered for {:04x}:{:04x}", vid, pid))?;
    let encoded = encoder.encode(&pages, &opts)?;
    eprintln!(
        "printer-studio: encoded {} byte(s) via {}",
        encoded.len(),
        encoder.name()
    );

    if let Some(path) = dry_run_out.as_ref() {
        fs::write(path, &encoded)
            .with_context(|| format!("writing dry-run output to {}", path.display()))?;
        eprintln!("printer-studio: dry-run output saved to {}", path.display());
    }

    if !confirmed {
        eprintln!(
            "printer-studio: not transmitting (need --i-know-what-im-doing). \
             dry-run output {}.",
            dry_run_out
                .as_ref()
                .map(|p| format!("at {}", p.display()))
                .unwrap_or_else(|| "discarded".into())
        );
        return Ok(());
    }

    let printer = UsbPrinter::open(PrinterId { vid, pid })?;
    eprintln!(
        "printer-studio: transmitting {} bytes to {} (EP 0x{:02x})",
        encoded.len(),
        printer
            .info()
            .product
            .as_deref()
            .unwrap_or("printer"),
        printer.bulk_out()
    );
    printer.write_job(&encoded)?;
    eprintln!("printer-studio: transfer complete");
    Ok(())
}

fn cmd_send_raw(file: PathBuf, vid: u16, pid: u16, confirmed: bool) -> Result<()> {
    if !confirmed {
        bail!(
            "refusing to transmit to a real printer without --i-know-what-im-doing.\n\
             A malformed QPDL stream can put the printer in a bad state or waste paper/toner.\n\
             Re-run with: printer-studio send-raw {} --i-know-what-im-doing",
            file.display()
        );
    }
    let data = fs::read(&file).with_context(|| format!("reading {}", file.display()))?;
    let printer = UsbPrinter::open(PrinterId { vid, pid })?;
    println!(
        "Sending {} bytes to {} (EP 0x{:02x})...",
        data.len(),
        printer.info().product.as_deref().unwrap_or("printer"),
        printer.bulk_out()
    );
    printer.write_job(&data)?;
    println!("Transfer complete. Watch the printer for output.");
    Ok(())
}
