#![recursion_limit = "128"]
#[macro_use]
extern crate helix;
extern crate chrono;

use chrono::{DateTime, NaiveDateTime, TimeZone, Utc};
use evtx::{EvtxParser, ParserSettings};
use std::path::PathBuf;
use std::time::SystemTime;

ruby! {
    class EventAfter {
        struct {
            ts: i64,
            rn: Option<u64>
        }

        def initialize(helix, ts: i64, rn: Option<u64>) {
            Self { helix, ts, rn }
        }

        def timestamp(&self) -> i64 { self.ts }

        def record_number(&self) -> Option<u64> { self.rn }
    }

    class EvtxLoader {
        struct {
            file_path: String,
            pb: std::path::PathBuf,
            events: Vec<String>,
            total: u64,
            modified_time: DateTime<Utc>,
            oldest_time: DateTime<Utc>,
            oldest_rn: u64
        }

        def initialize(helix, path: String) {
            let default = DateTime::<Utc>::from_utc(NaiveDateTime::from_timestamp(0, 0), Utc);

            Self {
                helix: helix,
                file_path: path.clone(),
                events: vec![],
                oldest_time: default,
                modified_time: default,
                oldest_rn: 0,
                total: 0,
                pb: PathBuf::from(path)
            }
        }

        def oldest_record_number(&self) -> u64 { self.oldest_rn }

        def oldest_timestamp(&self) -> i64 { self.oldest_time.timestamp() }

        def total_records(&self) -> u64 { self.total }

        def events(&mut self) -> Vec<String> {
            let settings = ParserSettings::default().indent(false);
            let mut total_records: u64 = 0;
            let mut output: Vec<String> = Vec::new();
            let mut parser = EvtxParser::from_path(&self.pb).
                unwrap().
                with_configuration(settings);

            for record in parser.records_json() {
                match record {
                    Ok(r) => {
                        output.push(r.data.to_string());

                        if r.timestamp > self.oldest_time {
                            self.oldest_rn = r.event_record_id;
                            self.oldest_time = r.timestamp;
                        }
                        total_records += 1;
                    },
                    Err(e) => eprintln!("{}", e),
                }
            }

            self.total = total_records;
            self.modified_time = Utc.timestamp(self.file_modified_time(), 0);

            output
        }

        def file_modified_time(&self) -> i64 {
          (std::fs::metadata(&self.file_path).
              unwrap().
              modified().
              unwrap().
              duration_since(SystemTime::UNIX_EPOCH).
              unwrap().
              as_secs()) as i64
        }

        def was_modified(&self) -> bool {
          if self.modified_time.timestamp() < self.file_modified_time() {
              return true;
          }

          false
        }
    }
}
