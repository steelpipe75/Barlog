#!/usr/bin/ruby -Ku

=begin

Barlog
https://github.com/steelpipe75/Barlog

Copyright(c) 2013 steelpipe75
Released under the MIT license.
https://github.com/steelpipe75/Barlog/blob/master/MIT-LICENSE.txt

Includes Kwalify
http://www.kuwata-lab.com/kwalify/
copyright(c) 2005-2010 kuwata-lab all rights reserved.
Released under the MIT License.

=end

###
### Barlog.rb
###
require 'pp'
require 'optparse'
require 'csv'
require 'yaml'
require 'kwalify'
require 'erb'
require 'json'

# parameter

Version = "v1.1.2"

# global variable
$inputfilename = "input.csv"
$outputfilename = "output.csv"
$convertfilename = "convert.yaml"

$stdout_str = []
$stderr_str = []

$SCHEMA_DEF = <<EOS
type: seq
sequence:
  - type: map
    mapping:
      "job":
        required: true
        enum: 
          - sort
          - script
          - hash
          - column_sort
      "key":
        required: true
        type: str
      "cond":
        type: str
      "param":
        required: true
        type: any
EOS

# option parser
def option_parse(argv)
  opt = OptionParser.new
  opt.on('-i inputfile',  '--input inputfile',        '入力ファイル指定')     { |v| $inputfilename = v }
  opt.on('-o outputfile', '--output outputfile',      '出力ファイル指定')     { |v| $outputfilename = v }
  opt.on('-c convertfile', '--convert convertfile',   '変換指示ファイル指定') { |v| $convertfilename = v }
  
  opt.parse(argv)
  
  $stdout_str.push sprintf("inputfile\t= \"%s\"\n",$inputfilename)
  $stdout_str.push sprintf("outputfile\t= \"%s\"\n",$outputfilename)
  $stdout_str.push sprintf("convertfile\t= \"%s\"\n",$convertfilename)
  $stdout_str.push "========================\n"
end

# validator
class FormatValidator < Kwalify::Validator
  @@schema = YAML.load($SCHEMA_DEF)
  
  def initialize()
    super(@@schema)
  end
  
end

def csv_convert(argv)
  option_parse(argv)
  
  begin
    table = CSV.read($inputfilename, headers:true, converters: :numeric)
  rescue => ex
    $stderr_str.push "Error: inputfile can not open\n"
    $stderr_str.push sprintf("\t%s\n" ,ex.message)
    return 1
  end
  
  if table.length == 0 then
    $stderr_str.push "Error: there is no data in the inputfile \n"
    return 1
  end
  
  begin
    c_file = File.read($convertfilename)
  rescue => ex
    $stderr_str.push "Error: convertfile can not open\n"
    $stderr_str.push sprintf("\t%s\n" ,ex.message)
    return 1
  end
  
  c_str = ""
  
  c_file.each_line { |line|
    while /\t+/ =~ line
      n = $&.size * 8 - $`.size % 8
      line.sub!(/\t+/, " " * n)
    end
    c_str << line
  }
  
  parser = Kwalify::Parser.new(c_str)
  yaml = parser.parse()
  validator = FormatValidator.new
  errors = validator.validate(yaml)
  
  if !errors || errors.empty? then
  else
    $stderr_str.push "Error: invalid format file\n"
    parser.set_errors_linenum(errors)
    errors.each { |error|
      $stderr_str.push sprintf( "\t%s (line %s) [%s] %s\n",$convertfilename,error.linenum,error.path,error.message)
    }
    return 1
  end
  
  yaml.each { |ptn|
    
    $stdout_str.push ptn.to_json + "\n"
    
    if ptn["job"] == "sort" then
      begin
        key = ptn["key"]
        if ptn["param"] == "ascending" then
          new_table = table.sort_by { |row| row[key] }
        else
          new_table = table.sort_by { |row| row[key] * -1 }
        end
        str = table.headers.to_csv
        new_table.each { |row|
          str = str + row.to_csv
        }
        table = CSV.parse(str, headers:true, converters: :numeric)
      rescue => ex
        $stderr_str.push "Error: exception in convert \n"
        $stderr_str.push sprintf("\t%s\n" ,ex.message)
        return 1
      end
    elsif ptn["job"] == "column_sort" then
      begin
        old_table = table.to_a.transpose
        tmp_table = old_table
        new_table = []
        ptn["param"].each { |k|
          tmp_table = []
          old_table.each { |c|
            if c[0] == k then
              new_table.push c
            else
              tmp_table.push c
            end
          }
          old_table = tmp_table
        }
        old_table.each { |c|
          new_table.push c
        }
        tmp_table = new_table.transpose
        str = tmp_table[0].to_csv
        tmp_table = tmp_table[1..tmp_table.size]
        tmp_table.each { |row|
          str = str + row.to_csv
        }
        table = CSV.parse(str, headers:true, converters: :numeric)
      rescue => ex
        $stderr_str.push "Error: exception in convert \n"
        $stderr_str.push sprintf("\t%s\n" ,ex.message)
        return 1
      end
    else
      table.each_with_index { |row, idx|
        begin
          flg = "false"
          if ptn["cond"] == nil then
            flg = "true"
          else
            erb = ERB.new(ptn["cond"])
            flg = erb.result(binding)
          end
          
          if flg == "true" then
            case ptn["job"]
            when "script"
              key = ptn["key"]
              val = row[key]
              script = ptn["param"][0]
              param = ptn["param"][1]
              erb = ERB.new(script)
              new_val = erb.result(binding)
              row[key] = new_val
            when "hash"
              key = ptn["key"]
              val = row[key]
              new_val = ptn["param"][val]
              if new_val == nil then
                row[key] = val
              else
                row[key] = new_val
              end
            end
          end
        rescue => ex
          $stderr_str.push sprintf("Error: exception in convert (row %d) \n" ,idx)
          $stderr_str.push sprintf("\t%s\n" ,ex.message)
          return 1
        end
      }
    end
  }
  
  begin
    File.open($outputfilename,"w") { |file|
      file.write table.to_csv
    }
  rescue => ex
    $stderr_str.push "Error: inputfile can not open\n"
    $stderr_str.push sprintf("\t%s\n" ,ex.message)
    return 1
  end
  
  return 0
end

# entry point
$stdout_str = []
$stderr_str = []
ret = csv_convert(ARGV)
$stdout_str.each do |str|
  STDOUT.puts(str)
end
puts "========================"
$stdout.flush
if ret != 0 then
  $stderr_str.each { |str|
    STDERR.puts(str)
  }
  exit ret
else
  puts "Success"
end
