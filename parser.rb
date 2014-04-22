require 'json'

require 'unicode'

require 'net/http'

require 'mongo'

require 'listen'

class ReportParser
  def self.parse report
    @report = {number: 0, receipts: []}
    @receipt = {time: nil, sum: nil, lines: []}

    report.lines.each do |line|
      next if summary_line line
      next if report_line line
      next if receipt_content line
      #next if date_line line
      if receipt_end line
        @report[:receipts] << @receipt
        @receipt = {time: nil, sum: nil, lines: []}
        next
      end
      next if report_line line
    end

    return @report
  end

  private

  def self.report_line line
    regex = /Z\sREADING\sNR\s+(?<number>\d+)/
    match = line.match regex
    if match
      @report[:number] = match[:number].to_i
      return true
    end
    return false
  end

  def self.date_line line
    if line =~ /^\/(\d{2})-(\d{2})-(\d{4})\s+(\d{2}):(\d{2})/
      @report[:start] = Time.local($3, $2, $1, $4, $5)
      return true
    end
    return false
  end

  def self.summary_line line
    return false
  end

  def self.receipt_content line
    regex = /^(?<type>\S)\s+(?<code>\d+)\s+(?<name>.{23})\s+(?<count>\d+)\s+(?<sum>\d+\.\d{2})/
    match = line.match regex
    if match
      line = {}
      if match[:type] == "c"
        return false
      elsif match[:type] == "A"
        line[:type] = :sale
      elsif match[:type] == "R"
        line[:type] = :payment
      elsif match[:type] == "x"
         line[:type] = :tax
      elsif match[:type] == "L"
        line[:type] = :cancelled_sale
      elsif match[:type] == "h"
        line[:type] = :drawer
      else
        line[:type] = :other
      end

      line[:code] = match[:code].to_i
      line[:name] = Unicode.capitalize match[:name].strip
      line[:sum] = match[:sum].to_f
      line[:count] = match[:count].to_i

      @receipt[:lines] << line

      return true
    end

    return false
  end

  def self.receipt_end line
    regex = /^\s<(?<day>\d{2})-(?<month>\d{2})-(?<year>\d{2}) (?<hour>\d{2}):(?<min>\d{2})(?<num>\d+)\/\d\s+(?<sum>\d+\.\d+)/
    match = line.match regex
    if match
      @receipt[:time] = Time.local(match[:year].to_i+2000,
                                 match[:month].to_i,
                                 match[:day].to_i,
                                 match[:hour].to_i,
                                 match[:min].to_i)
      @receipt[:number] = match[:num].to_i
      @receipt[:sum] = match[:sum].to_f

      return true
    end

    return false
  end
end

  db = Mongo::MongoClient.new("localhost").db("zrapport")
  @reports = db[:reports]
  @receipts = db[:receipts]

  def process_file file
    return unless /.*\.DT.$/ =~ file

    puts "Processing: #{file}"

    File.open(file) do |f|
      report = ReportParser.parse(f.read.force_encoding("iso8859-1"))

      begin
        id = @reports.insert({number: report[:number]})

        report[:receipts].each do |receipt|
          receipt[:report_id] = id
          @receipts.insert(receipt)
        end
      rescue => e
        puts "Receipt #{report[:number]} is already in the database"
      end

      #http = Net::HTTP.new("zthingy.dev")
      #puts http.request_put('/add_report', json, {"Content-Type" => "text/json; charset=ISO-8859-1"}).body
    end
  end

  def process_dir dir
    puts "Opening #{dir.inspect}"
    Dir.foreach(dir) do |file|
      if file == "." || file == ".."
        next
      elsif File.directory? "#{dir}/#{file}"
        process_dir "#{dir}/#{file}"
      else
        process_file "#{dir}/#{file}"
      end
    end
  end

  l = Listen.to("#{Dir.home}/Dropbox/CYB - Økonomi/zrapport", only: /\.DT[0-9T]/) do |m, a, d|
  for f in a do
  process_file f
  end
  end

  l.start

  sleep
