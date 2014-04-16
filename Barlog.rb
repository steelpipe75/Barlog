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
require 'tk'

# parameter

Version = "v1.1"

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
      begin
        table.each_with_index { |row, idx|
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
        }
      rescue => ex
        $stderr_str.push sprintf("Error: exception in convert (row %d) \n" ,idx)
        $stderr_str.push sprintf("\t%s\n" ,ex.message)
        return 1
      end
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



# gui(tk)
def getopenconvertfile
  return Tk.getOpenFile('title' => 'ファイルを開く',
                        'defaultextension' => 'sgf', 
                        'filetypes' => "{YAMLファイル {.yaml}} {全てのファイル {.*}}")
end

def getopeninputfile
  return Tk.getOpenFile('title' => 'ファイルを開く',
                        'defaultextension' => 'sgf', 
                        'filetypes' => "{CSVファイル {.csv}} {全てのファイル {.*}}")
end

def getsavefile
  return Tk.getSaveFile('title' => 'ファイルを開く',
                        'defaultextension' => 'sgf', 
                        'filetypes' => "{CSVファイル {.csv}} {全てのファイル {.*}}")
end

def start_gui
  convertfile_var = TkVariable.new('')
  inputfile_var = TkVariable.new('')
  outputfile_var = TkVariable.new('')

  gui_title = sprintf("Barlog %s", Version)

  window = TkRoot.new {
    title gui_title
    resizable [0,0]
  }

  fomrat_row = 0

  convertlabel = TkLabel.new {
    text 'convertfile'
    width 10
    anchor 'w'
    grid 'row'=>fomrat_row, 'column'=>0, 'sticky' => 'news'
  }

  convertfile = TkEntry.new {
    width 40
    grid 'row'=>fomrat_row, 'column'=>1, 'sticky' => 'news'
  }

  convertfile.textvariable = convertfile_var

  convertbutton = TkButton.new {
    text 'select'
    width 10
    grid 'row'=>fomrat_row, 'column'=>2, 'sticky' => 'news'
  }

  convertbutton.command( proc{ convertfile.value = getopenconvertfile } )

  input_row = 1

  inputlabel = TkLabel.new {
    text 'inputfile'
    width 10
    anchor 'w'
    grid 'row'=>input_row, 'column'=>0, 'sticky' => 'news'
  }

  inputfile = TkEntry.new {
    width 40
    grid 'row'=>input_row, 'column'=>1, 'sticky' => 'news'
  }

  inputfile.textvariable = inputfile_var

  inputbutton = TkButton.new {
    text 'select'
    width 10
    grid 'row'=>input_row, 'column'=>2, 'sticky' => 'news'
  }

  inputbutton.command( proc{ inputfile.value = getopeninputfile } )

  output_row = 2

  outputlabel = TkLabel.new {
    text 'outputfile'
    width 10
    anchor 'w'
    grid 'row'=>output_row, 'column'=>0, 'sticky' => 'news'
  }

  outputfile = TkEntry.new {
    width 40
    grid 'row'=>output_row, 'column'=>1, 'sticky' => 'news'
  }

  outputfile.textvariable = outputfile_var

  outputbutton = TkButton.new {
    text 'select'
    width 10
    grid 'row'=>output_row, 'column'=>2, 'sticky' => 'news'
  }

  outputbutton.command( proc{ outputfile.value = getsavefile } )

  exec_row = 3

  execbutton = TkButton.new {
    text 'exec'
    grid 'row'=>exec_row, 'column'=>0, 'columnspan'=>3, 'sticky' => 'news'
  }

  resultlabel = TkLabel.new {
    text 'result'
    width 10
    anchor 'w'
    grid 'row'=>exec_row+1, 'column'=>0, 'sticky' => 'news'
  }

  result_text = TkText.new {
    state 'disabled'
    height 10
    grid 'row'=>exec_row+2, 'column'=>0, 'columnspan'=>3, 'sticky' => 'news'
  }

  execbutton.command(
    proc {
      $stdout_str = []
      $stderr_str = []
      result_text.state 'normal'
      result_text.delete('0.0', 'end')
      gui_arg = []
      if convertfile_var.to_s.length > 0 then
        gui_arg.push '-c'
        gui_arg.push convertfile_var.to_s
      end
      if inputfile_var.to_s.length > 0 then
        gui_arg.push '-i'
        gui_arg.push inputfile_var.to_s
      end
      if outputfile_var.to_s.length > 0 then
        gui_arg.push '-o'
        gui_arg.push outputfile_var.to_s
      end
      csv_convert(gui_arg)
      $stdout_str.each do |str|
        result_text.insert('end', str)
      end
      separator = sprintf("========================\n")
      result_text.insert('end', separator)
      if $stderr_str.empty? then
        result_text.insert('end', 'Success')
      else
        $stderr_str.each do |str|
         result_text.insert('end', str)
        end
      end
      result_text.state 'disabled'
    }
  )

  Tk.mainloop
end



# entry point
if ARGV.empty? then
  start_gui
else
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
end
