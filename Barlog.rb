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
end

option_parse(ARGV)

table = CSV.table($inputfilename)
yaml = YAML.load_file($convertfilename)

yaml.each { |ptn| 
  table.each { |row| 
    key = ptn["key"].to_sym
    val = row[key]
    new_val = ptn["hash"][val]
    if new_val == nil then
      row[key] = val
    else
      row[key] = new_val
    end
  }
}

File.open($outputfilename,"w") do |file|
  file.write table.to_csv
end
