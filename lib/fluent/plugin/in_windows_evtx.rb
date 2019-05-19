#
# Copyright 2019- TODO: Write your name
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "helix_runtime"
require "fluent-plugin-windows-evtx/native"
require "fluent/plugin/input"
require 'fluent/plugin'
module Fluent::Plugin
  class WindowsEvtxInput < Fluent::Plugin::Input
	Fluent::Plugin.register_input("windows_evtx", self)

    helpers :timer, :storage

    DEFAULT_STORAGE_TYPE = 'local'
    KEY_MAP = {"record_number" => [:record_number, :string],
                 "time_generated" => [:time_generated, :string],
                 "time_written" => [:time_written, :string],
                 "event_id" => [:event_id, :string],
                 "event_type" => [:event_type, :string],
                 "event_category" => [:category, :string],
                 "source_name" => [:source, :string],
                 "computer_name" => [:computer, :string],
                 "user" => [:user, :string],
                 "description" => [:description, :string],
                 "string_inserts" => [:string_inserts, :array]}

    config_param :file, :string
    config_param :tag, :string
    config_param :read_interval, :time, default: 2
    config_param :pos_file, :string, default: nil,
                 obsoleted: "This section is not used anymore. Use 'store_pos' instead."
    config_param :keys, :array, default: []
    config_param :read_from_head, :bool, default: false
    config_param :from_encoding, :string, default: nil
    config_param :encoding, :string, default: nil

    config_section :storage do
      config_set_default :usage, "positions"
      config_set_default :@type, DEFAULT_STORAGE_TYPE
      config_set_default :persistent, true
    end

    attr_reader :chs

    def initialize
      super
      @keynames = []
      @tails = {}
    end

    def configure(conf)
      super
      if @file.empty?
        raise Fluent::ConfigError, "windows_evtx: 'file' parameter is required on windows_evtx input"
      end
      @keynames = @keys.map {|k| k.strip }.uniq
      if @keynames.empty?
        @keynames = KEY_MAP.keys
      end

      @tag = tag
      @stop = false
      configure_encoding
      @receive_handlers = if @encoding
                            method(:encode_record)
                          else
                            method(:no_encode_record)
                          end
      @pos_storage = storage_create(usage: "positions")
    end

    def configure_encoding
      unless @encoding
        if @from_encoding
          raise Fluent::ConfigError, "windows_evtx: 'from_encoding' parameter must be specied with 'encoding' parameter."
        end
      end

      @encoding = parse_encoding_param(@encoding) if @encoding
      @from_encoding = parse_encoding_param(@from_encoding) if @from_encoding
    end

    def parse_encoding_param(encoding_name)
      begin
        Encoding.find(encoding_name) if encoding_name
      rescue ArgumentError => e
        raise Fluent::ConfigError, e.message
      end
    end

    def encode_record(record)
      if @encoding
        if @from_encoding
          record.encode!(@encoding, @from_encoding)
        else
          record.force_encoding(@encoding)
        end
      end
    end

    def no_encode_record(record)
      record
    end

    def start
      super
      start, num = @pos_storage.get(ch)
      @file = EvtxLoader.open(ch)
      if @read_from_head || (!num || num.zero?)
        @pos_storage.put(ch, [el.oldest_record_number - 1, 1])
      end
      timer_execute("in_windows_evtx_#{@file}".to_sym, @read_interval) do
        on_notify(@file)
      end
    end

    def receive_lines(ch, lines)
      return if lines.empty?
      begin
        for r in lines
          h = {"channel" => ch}
          @keynames.each do |k|
            type = KEY_MAP[k][1]
            value = r.send(KEY_MAP[k][0])
            h[k]=case type
                 when :string
                   @receive_handlers.call(value.to_s)
                 when :array
                   value.map {|v| @receive_handlers.call(v.to_s)}
                 else
                   raise "Unknown value type: #{type}"
                 end
          end
          #h = Hash[@keynames.map {|k| [k, r.send(KEY_MAP[k][0]).to_s]}]
          router.emit(@tag, Fluent::Engine.now, h)
        end
      rescue => e
        log.error "unexpected error", error: e
        log.error_backtrace
      end
    end

    def on_notify(ch)
      current_oldest_record_number = @file.oldest_record_number
      current_total_records = el.total_records

      read_start, read_num = @pos_storage.get(ch)

      # if total_records is zero, oldest_record_number has no meaning.
      if current_total_records == 0
        return
      end

      if read_start == 0 && read_num == 0
        @pos_storage.put(ch, [current_oldest_record_number, current_total_records])
        return
      end

      current_end = current_oldest_record_number + current_total_records - 1
      old_end = read_start + read_num - 1

      if current_oldest_record_number < read_start
        # may be a record number rotated.
        current_end += 0xFFFFFFFF
      end

      if current_end < old_end
        # something occured.
        @pos_storage.put(ch, [current_oldest_record_number, current_total_records])
        return
      end

      winlogs = el.read(Win32::EventLog::SEEK_READ | Win32::EventLog::FORWARDS_READ, old_end + 1)
      receive_lines(ch, winlogs)
      @pos_storage.put(ch, [read_start, read_num + winlogs.size])
    ensure
      el.close
    end

    def to_key(key)
      key.downcase!
      key.gsub!(' '.freeze, '_'.freeze)
      key
    end
  end
end
