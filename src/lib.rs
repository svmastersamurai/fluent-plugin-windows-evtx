#[macro_use]
extern crate helix;

use evtx::EvtxParser;
use std::path::PathBuf;

ruby! {
    class EvtxLoader {
        struct {
            file_path: String,
            pb: std::path::PathBuf,
            orn: u64
        }

        def initialize(helix, path: String) {
            Self {
                helix: helix,
                file_path: path.clone(),
                orn: 0,
                pb: PathBuf::from(path),
            }
        }
        def oldest_record_number(&self) -> u64 { self.orn }
        def to_s(&mut self) -> String {
            let mut output = String::new();
            let mut parser = EvtxParser::from_path(&self.pb).unwrap();
            let mut last_record: u64 = 0;

            for record in parser.records_json() {
                last_record += 1;
                match record {
                    Ok(r) => output.push_str(&r.data),
                    Err(e) => eprintln!("{}", e),
                }
            }

            self.orn = last_record;

            output
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(2 + 2, 4);
    }
}
