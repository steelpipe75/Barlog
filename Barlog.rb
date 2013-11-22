#!/usr/bin/ruby -Ku

=begin

Barlog
https://github.com/steelpipe75/Barlog

Copyright(c) 2013 steelpipe75
Released under the MIT license.
https://github.com/steelpipe75/Barlog/blob/master/MIT-LICENSE.txt

=end

###
### Barlog.rb
###
require 'pp'
require 'optparse'
require 'csv'
require 'yaml'
require 'erb'

# parameter

Version = "v0.1"

$inputfilename = "input.csv"
$outputfilename = "output.csv"
$convertfilename = "convert.yaml"

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

option_parse(ARGV)

table = CSV.table($inputfilename)
yaml = YAML.load_file($convertfilename)

yaml.each { |ptn| 
  if ptn["job"] == "sort" then
    str = []
    key = ptn["key"].to_sym
    if ptn["param"] == "ascending" then
      new_table = table.sort_by { |row| row[key] }
    else
      new_table = table.sort_by { |row| row[key] * -1 }
    end
    str = table.headers.to_csv
    new_table.each { |row|
      str = str + row.to_csv
    }
    table = CSV.parse(str, headers:true, converters: :numeric, header_converters: :symbol)
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
          key = ptn["key"].to_sym
          val = row[key]
          erb = ERB.new(ptn["param"])
          new_val = erb.result(binding)
          row[key] = new_val.to_i
        when "hash"
          key = ptn["key"].to_sym
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

File.open($outputfilename,"w") do |file|
  file.write table.to_csv
end
