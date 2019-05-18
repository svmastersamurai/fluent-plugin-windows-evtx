#[macro_use]
extern crate helix;

use evtx::EvtxParser;
use std::path::PathBuf;

pub fn load_evtx(path: String) {
    let fp = PathBuf::from(path); 
    
    let mut parser = EvtxParser::from_path(fp).unwrap();
    for record in parser.records() {
        match record {
            Ok(r) => println!("Record {}\n{}", r.event_record_id, r.data),
            Err(e) => eprintln!("{}", e),
        }
    }
}

ruby! {
    class EvtxLoader {
        def load(path: String) {
            println!("Woulda loaded {}", path);
            load_evtx(path);
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
