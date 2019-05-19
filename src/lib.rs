#[macro_use]
extern crate helix;
extern crate chrono;

use chrono::{DateTime, NaiveDateTime, Utc};
use evtx::{EvtxParser, ParserSettings};
use std::path::PathBuf;

ruby! {
    class EvtxLoader {
        struct {
            file_path: String,
            pb: std::path::PathBuf,
            total: u64,
            modified_time: DateTime<Utc>,
            oldest_time: DateTime<Utc>,
            oldest_rn: u64
        }

        def initialize(helix, path: String) {
            Self {
                helix: helix,
                file_path: path.clone(),
                oldest_time: DateTime::<Utc>::from_utc(NaiveDateTime::from_timestamp(0, 0), Utc),
                oldest_rn: 0,
                total: 0,
                pb: PathBuf::from(path),
            }
        }

        def oldest_record_number(&self) -> u64 { self.oldest_rn }

        def oldest_timestamp(&self) -> i64 { self.oldest_time.timestamp() }

        def total_records(&self) -> u64 { self.total }

        def to_s(&mut self) -> String {
            let settings = ParserSettings::default().indent(false);
            let mut total_records: u64 = 0;
            let mut output: Vec<String> = Vec::new();
            let mut parser = EvtxParser::from_path(&self.pb).
                unwrap().
                with_configuration(settings);

            for record in parser.records_json() {
                match record {
                    Ok(r) => {
                        output.push(format!("{}", &r.data));

                        if &r.timestamp > &self.oldest_time {
                            self.oldest_rn = r.event_record_id;
                            self.oldest_time = r.timestamp;
                        }
                        total_records += 1;
                    },
                    Err(e) => eprintln!("{}", e),
                }
            }

            self.total = total_records;
            format!("[{}]", output.join(","))
        }
    }
}
