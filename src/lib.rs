#[macro_use]
extern crate helix;

use evtx::{EvtxParser, ParserSettings};
use std::path::PathBuf;

ruby! {
    class EvtxLoader {
        struct {
            file_path: String,
            pb: std::path::PathBuf,
            total: u64,
            oldest: u64
        }

        def initialize(helix, path: String) {
            Self {
                helix: helix,
                file_path: path.clone(),
                oldest: 0,
                total: 0,
                pb: PathBuf::from(path),
            }
        }

        def oldest_record_number(&self) -> u64 { self.oldest }

        def total_records(&self) -> u64 { self.total }

        def to_s(&mut self) -> String {
            let settings = ParserSettings::default().indent(false);
            let mut output: Vec<String> = Vec::new();
            let mut last_record: u64 = 0;
            let mut parser = EvtxParser::from_path(&self.pb).
                unwrap().
                with_configuration(settings);

            for record in parser.records_json() {
                last_record += 1;
                match record {
                    Ok(r) => {
                        output.push(format!("{}", &r.data));
                    },
                    Err(e) => eprintln!("{}", e),
                }
            }

            self.oldest = last_record;

            format!("[{}]", output.join(","))
        }
    }
}
