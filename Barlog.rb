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

# parameter

Version = "v0.1"

# global variable
$inputfilename = "input.csv"
$outputfilename = "output.csv"
$convertfilename = "convert.yaml"

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

  puts sprintf("inputfile\t= \"%s\"\n",$inputfilename)
  puts sprintf("outputfile\t= \"%s\"\n",$outputfilename)
  puts sprintf("convertfile\t= \"%s\"\n",$convertfilename)
end

# validator
class FormatValidator < Kwalify::Validator
  @@schema = YAML.load($SCHEMA_DEF)

  def initialize()
    super(@@schema)
  end

end

# entry point

option_parse(ARGV)

table = CSV.read($inputfilename, headers:true, converters: :numeric)

begin
  c_file = File.read($convertfilename)
rescue => ex
  STDERR.puts "Error: convertfile can not open\n"
  STDERR.puts sprintf("\t%s\n" ,ex.message)
  exit 1
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
  STDERR.puts "Error: invalid format file\n"
  parser.set_errors_linenum(errors)
  errors.each { |error|
    STDERR.puts sprintf( "\t%s (line %s) [%s] %s\n",$convertfilename,error.linenum,error.path,error.message)
  }
  exit 1
end

yaml.each { |ptn|
  if ptn["job"] == "sort" then
    str = []
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
    str = []
  else
    table.each { |row|
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
      flg = "false"
    }
  end
}

File.open($outputfilename,"w") { |file|
  file.write table.to_csv
}
