#
# Copyright 2019- Dan Sedlacek
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

    config_param :file_path, :string
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

    def evtx_log
      @evtx_log
    end

    def configure(conf)
      super
      if @file_path.empty?
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
      start, num = @pos_storage.get(@file_path)
      @evtx_log = EvtxLoader.new(@file_path)
      if @read_from_head || (!num || num.zero?)
        @pos_storage.put(@file_path, [@evtx_log.oldest_record_number - 1, 1])
      end
      timer_execute("in_windows_evtx_#{@file_path}".to_sym, @read_interval) do
        on_notify(@file_path)
      end
    end

    def receive_lines(lines)
      return if lines.empty?
      begin

        for r in lines.map {|l| convert_hash_keys(l) }
          h = {'time' => Time.iso8601(r['event']['system']['time_created']['#attributes']['system_time']).to_i}.
            merge!(r['event']['system']).
            merge!(r['event']['event_data']).
            reject! { |k| k =~ /time_created/ }
          router.emit(@tag, Fluent::Engine.now, h.compact.to_json)
        end
      rescue => e
        log.error "unexpected error", error: e
        log.error_backtrace
      end
    end

    def on_notify(_ch)
      events = JSON.parse(@evtx_log.to_s)
      current_oldest_record_number = @evtx_log.oldest_record_number
      current_total_records = @evtx_log.total_records
      read_start, read_num = @pos_storage.get(@file_path)

      if read_start == 0 && read_num == 0
        @pos_storage.put(@file_path, [current_oldest_record_number, current_total_records])
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
        @pos_storage.put(@file_path, [current_oldest_record_number, current_total_records])
        return
      end

      receive_lines(events)
      @pos_storage.put(@file_path, [read_start, read_num + events.length])
    end

	def convert_hash_keys(value)
	  case value
	  when Array
		value.map(&:convert_hash_keys)
	  when Hash
		Hash[value.map { |k, v| [to_key(k.dup), convert_hash_keys(v)] }]
	  else
		value
	  end
	end

	def to_key(key)
      key.gsub(/::/, '/').
		gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
		gsub(/([a-z\d])([A-Z])/,'\1_\2').
		tr("-", "_").
		tr(" ", "_").
		downcase
	end
  end
end
