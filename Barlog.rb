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
  case ptn["job"]
  when "script"
    table.each { |row| 
      flg = "false"
      if ptn["cond"] == nil then
        flg = "true"
      else
        erb = ERB.new(ptn["cond"])
        flg = erb.result(binding)
      end
      
      if flg == "true" then
        key = ptn["key"].to_sym
        val = row[key]
        erb = ERB.new(ptn["param"])
        new_val = erb.result(binding)
        row[key] = new_val.to_i
      end
    }
  when "hash"
    table.each { |row| 
      flg = "false"
      if ptn["cond"] == nil then
        flg = "true"
      else
        erb = ERB.new(ptn["cond"])
        flg = erb.result(binding)
      end
      
      if flg == "true" then
        key = ptn["key"].to_sym
        val = row[key]
        new_val = ptn["param"][val]
        if new_val == nil then
          row[key] = val
        else
          row[key] = new_val
        end
      end
    }
  end
}

File.open($outputfilename,"w") do |file|
  file.write table.to_csv
end
