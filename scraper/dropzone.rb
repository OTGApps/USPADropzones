# require 'json'
require 'open-uri'
require 'bundler'
require 'json'
Bundler.require
require './string'
require './states'

require 'csv'

class DZScraper
  attr_accessor :aircraft

  def initialize
    cache_files_locally

    pretty = true
    result = scrape

    # Shows all unique aircraft strings
    # puts "*" * 10
    # pp @aircraft.flatten.uniq.sort
    # puts "*" * 10

    File.open("../dropzones.geojson","w") do |f|
    # File.open("../../Dropzones/app/models/root-store/dropzones.json","w") do |f|
        f.write(pretty ? JSON.pretty_generate(result) : result.to_json)
    end
  end

  def cache_files_locally
    # Get the main dz locator page:
    file_name = "local_files/000_all.html"
    unless File.file?(file_name)
      puts "Writing file to: " + file_name
      agent.get("https://uspa.org/dzlocator").save(file_name)
    end

    # Extract all the places
    lines = []
    File.open(file_name).each do |line|
      lines << line.strip if line.strip.start_with?('markers.push') || line.strip.start_with?('infoWindowContent.push')
    end

    # Parse the places
    places = {}
    lines.each_with_index do |l, index|
      next if index.odd?

      account = lines[index+1].scan(/<([^>]*)>/).find{|a| a.first.include?('accountnumber')}.first
      if account
        account_number = account.split('=').last

        # Now get the name and lat/long
        data = l.gsub('markers.push([', '').gsub(']);', '')
        parsed_data = CSV.parse(data, :converters=> lambda {|f| f ? f.strip : nil}, :quote_char => "'").first
        places[account_number] = {
          name: parsed_data[0],
          latitude: parsed_data[1],
          longitude: parsed_data[2],
         }
      end
    end

    # Now that we have a list of the places and their lat/long, lets get their
    # details.

    places.keys.each do |place_account|
      file_name = "local_files/dropzone/#{place_account}.html"
      unless File.file?(file_name)
        puts "Writing file to: " + file_name
        agent.get(location_url(place_account)).save(file_name)
      end
    end

  end

  def skip_anchors
    @_skip_anchors ||= [
      260335, # Military Only
      238840, # Military Only
      261413, # Military Club
      206689, # Not a dropzone
      196509, # Military only
      100490, # Blue Sky Ranch is Skydive the ranch's school
    ]
  end

  def scrape
    dzs = {
      type: 'FeatureCollection',
      features: []
    }
    all_files.map do |lf|
      anchor = lf.split("/").last.split(".").first.to_i

      if skip_anchors.include?(anchor)
        puts "SKIPPING #{lf}"
        next
      end

      puts "Scraping #{lf}"
      html = open(lf)
      page = Nokogiri::HTML(html)
      page.xpath("//script").remove
      data_we_care_about = page.css('.mx-product-details-template .col-sm-10').first

      parsed = parse(data_we_care_about, anchor)

      # These two aren't in the data_we_care_about variable so we have to get it outside that code block.
      parsed[:properties][:training] = page.css('#dnn_ctr1586_ContentPane').css('p').last.parent.parent.parent.parent.text.split('##LOC[Cancel]##').last.strip.split("\r\n")
      parsed[:properties][:services] = page.css('#dnn_ctr1585_ModuleContent').css('p').last.parent.parent.parent.parent.text.split('##LOC[Cancel]##').last.strip.split("\r\n")

      # Sort by key
      parsed[:properties] = parsed[:properties].sort.to_h

      dzs[:features] << parsed #unless skip_anchors.include?(parsed[:properties][:anchor].to_i)
    end
    dzs[:features] = dzs[:features].sort_by{|f| f[:properties][:name]}
    # pp dzs
    dzs
  end

  def parse(page, anchor)
    dz_data = {
      type: 'Feature',
      properties: {},
      geometry: {
        type: 'Point',
        coordinates: []
      }
    }

    dz_data[:properties][:anchor] = anchor
    dz_data[:properties][:name] = page.css('h2').first.text.chomp.strip
    pp 'name: ' + dz_data[:properties][:name]

    # Grab the lat and lng
    dz_data[:geometry][:coordinates] = parse_lat_lng(page).reverse

    dz_data[:properties][:website] = page.css('.fa-external-link').first.next_element.text
    dz_data[:properties][:phone] = page.css('.fa-phone').first.next_element.text.chomp.strip
    dz_data[:properties][:email] = page.css('.fa-envelope').first.next_element.text.chomp.strip
    dz_data[:properties][:aircraft] = parse_aircraft_string(page.css('.fa-plane').first.next_sibling.text.gsub(/[[:space:]]/, ' ').strip)
    dz_data[:properties][:description] = page.css('hr').first.next_element.text.chomp.strip
    dz_data[:properties][:location] = parse_location_array(page)

    @aircraft ||= []
    @aircraft.concat(dz_data[:properties][:aircraft])

    dz_data
  end

  def parse_location_array(page)
    children = page.css('p').children
    children.shift
    first_i = children.find_index { |e| e.name == 'i' }
    location_array = children[0..first_i].search('~ br').map{|br| br.next.text.strip}.reject(&:empty?)
    location_array.map{|l| l.strip.gsub(/[[:space:]]/, ' ').gsub(/\s+/, ' ') }
  end

  def parse_aircraft_string(aircraft)
    new_value = aircraft.split(" and/or ").join(", ")
    new_value.split(", ").map do |a|
      new_a = a.split("--").first.chomp(" ").chomp(",")
        .titleize([
          '750xl',
          '750xstol',
          'Ptg-A21',
          'an-28',
          'Y-12s',
          'Mi-8'
        ])

      # Regexes
      new_a.gsub!(/C-([0-9]{3})/, 'Cessna \1')

      # Substitutions
      {
        "Cessna 182e" => "Cessna 182",
        "C 172" => "Cessna 172",
        "Dc-9" => "DC-9",
        "Dc3" => "DC-3",
        "Super  Otter" => "Super Twin Otter",
        "Pac750" => "PAC 750",
        "Cessna 208b" => "Cessna 208 Caravan",
        "1 AN-" => "1 Antonov ",
        "1 An-" => "1 Antonov ",
        "1  1 " => "1 ",
        "Ceena" => "Cessna",
        " - Ptg-A21 Turbo Prop" => "",
        "1 Caravan" => "1 Cessna 208 Caravan",
        "Supervan 900" => "Supervan",
        "Cessna 208B" => "Cessna 208",
        "Cessna Caravan 208" => "Cessna 208 Caravan",
        "Cessna172" => "Cessna 172",
        "Tbc-2mc" => "TBC-2MC",
        "182l" => "182",
        "900 Supervan" => "Supervan",
        "Cessna Caravans" => "Cessna 208 Caravans",
        " Cessna 208s" => " Cessna 208 Caravan",
      }.each do |key, value|
        new_a.gsub!(key, value)
      end

      # Whole replacements
      {
        '1 208' => '1 Cessna 208 Caravan',
        '1 850HP Cessna 208 Caravan' => '1 Cessna 208 Super Caravan',
        '1 An-2' => '1 AN-2',
        '1 Cessna Caravan' => '1 Cessna 208 Caravan',
        '1 Cessna Caravan Supervan' => '1 Cessna 208 Supervan',
        '3 Supervans' => '3 Cessna 208 Supervans',
        '1  1 Short C23 Sherpa' => '1 Short C23 Sherpa'
        # '1 Beech 99 King Air' => [
        #   '1 Beech 99',
        #   '1 King Air'
        # ]
      }.each do |key, value|
        new_a = value if new_a.downcase === key.downcase
      end

      # Eject here if out new_a is an array
      return new_a if new_a.is_a?(Array)

      # Search with whole replacement
      {
        'Blackhawk' => 'Cessna 208 Caravan Blackhawk',
        'Piper' => 'Piper Navajo PA31',
        'Porter' => 'Pilatus Porter PC-6 B2/H4',
        '410' => 'Let L-410 Turbolet'
      }.each do |key, value|
        new_a = new_a[0] + ' ' + value if new_a.downcase.include?(key.downcase)
      end

      # Fix issues with plurals
      qty = new_a[0].to_f
      new_a << "s" if (qty > 1) && !new_a.end_with?("s")
      new_a = new_a[0...-1] if new_a.start_with?("1") && new_a.end_with?("s")

      # Make sure they all start with a number.
      new_a = '1 ' + new_a if !new_a.match(/^(\d )/) && new_a.downcase != 'varies'

      new_a
    end.flatten.compact
  end

  def parse_lat_lng(page)
    links = page.css('a').map(&:values).flatten
    google_links =  links.select do |item|
      item.start_with?('https://www.google.com/maps/place/')
    end

    link = google_links.first
    coords = link.split('/@').last.split(',')[0..1]

    # fix a couple issues with the data.
    coords = coords.map{|ll| ll.gsub("30-", "30.").gsub("/", "") }

    coords.map(&:to_f)
  end

  def all_files
    Dir["local_files/dropzone/*.html"]
  end

  def location_url(location)
    "https://uspa.org/DZdetails?accountnumber=#{location}"
  end

  def agent
    @_agent ||= Mechanize.new { |agent|
      agent.user_agent_alias = 'Mac Safari'
    }
  end

end

dzs = DZScraper.new
