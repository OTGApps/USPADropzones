require 'json'
require 'open-uri'
require 'bundler'
Bundler.require

class String
  def string_between_markers marker1, marker2
    self[/#{Regexp.escape(marker1)}(.*?)#{Regexp.escape(marker2)}/m, 1]
  end

  def titleize
    split(/(\W)/).map(&:capitalize).join
  end

  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end
end

class DZScraper
  def urls
    page = Nokogiri::HTML(open(local_files.first))
    page.css('div#NavTabs li.Level2 a').map{ |e| URI.parse(e[:href]) }
  end

  def local_files
    Dir["local_files/*.html"]
  end

  def scrape_local
    scrape(local_files)
  end

  def scrape_online
    scrape(urls)
  end

  def scrape(urls)
    dzs = {
      type: 'FeatureCollection',
      features: []
    }
    urls.map do |lf|
      puts "Scraping #{lf}"
      html = open(lf)

      # if lf.to_s.start_with?("http")
      #   # Save the data
      #   state = lf.to_s.split('/')[5].underscore
      #   File.open("local_files/#{state}.html","w") do |f|
      #     f.write(html.read)
      #   end
      # end

      page = Nokogiri::HTML(html)
      dzs[:features] += parse(page).compact
    end
    dzs
  end

  def parse(page)
    page.css('table').last.css('td').map do |td|
      next if td.text.strip == '' || !td.text.include?("LAT:")

      dz_data = {
        type: 'Feature',
        properties: {},
        geometry: {
          type: 'Point',
          coordinates: []
        }
      }

      dz_data[:properties][:anchor] = td.css('a').first['name']
      dz_data[:properties][:name] = td.css('span.subhead').first.text.chomp.strip

      website = td.css('span.subhead').first.parent.css('a')
      dz_data[:properties][:website] = website.first[:href] unless website.empty?

      url = td.css('a[target="_blank"]')
      dz_data[:properties][:url] = url.first['href'] if url.is_a?(Array)

      dz_data[:properties].merge!(attributes(td))

      # Grab the lat and lng
      dz_data[:geometry][:coordinates] = [dz_data[:properties][:lng].to_f, dz_data[:properties][:lat].to_f]

      # Fix Skydive Taft
      if dz_data[:properties][:lng].start_with?("-199")
        dz_data[:geometry][:coordinates][0] = dz_data[:properties][:lng].gsub('199', '119').to_f
      end

      # Fix Oklahoma Skydiving Center && Skydive Chelan
      if dz_data[:properties][:anchor] == '37420' || dz_data[:properties][:anchor] == '33289'
        dz_data[:geometry][:coordinates][0] = ("-" + dz_data[:properties][:lng]).to_f
      end

      # Remove lat and lng from the properties array
      dz_data[:properties].reject!{ |k| k == :lat || k == :lng }

      dz_data
    end
  end

  def attributes(xml)
    atts = {}
    xml.css('span').select{|s| s.to_s.strip != ''}.each do |s|
      text = s.text.strip.delete('-')
      text = text.split(' ').last if text.start_with?('USPA') || text.strip.end_with?('Services:')
      text = text.split(' ').first if text.start_with?('Distance')
      text = text[0...-1] if text[-1] == ':'
      ts = text.downcase.to_sym

      atts[:email] = js_to_string(s.next_element).strip if ts == :email

      next if text.start_with?("*") || s.next_sibling.text.strip == ""
      atts[ts] = s.next_sibling.text.strip
    end

    atts[:location] = get_location(xml).map(&:strip)
    atts[:description] = get_description(xml)
    [:services, :training, :aircraft].each do |s|
      if atts[s]
        # Fix Aircraft
        atts[s].sub!('1 206', '1 Cessna 206')
        atts[s].sub!('1 208 Caravan', '1 Cessna 208 Caravan')

        atts[s] = atts[s].split(',').map{|a| a.strip }
      end
    end

    # Fix Training
    atts[:training] = atts[:training].reject{|t| t.downcase == 'not reported' } if atts[:training]

    # Fix Aircraft
    atts[:aircraft] = atts[:aircraft].map(&:titleize) if atts[:aircraft]

    atts
  end

  # This translates the obfuscated email address from javascript
  def js_to_string(js)
    xml = js.text.string_between_markers('String.fromCharCode(', '))').split(',').map{|i| i.to_i.chr(Encoding::UTF_8)}.join
    Nokogiri::HTML(xml).css('a').text.strip
  end

  # Finds the location array in the HTML
  def get_location(xml)
    loc_array = xml.to_s.string_between_markers('Location:</span>', '<br><br>')
      .split("\r\n")
      .select{ |s| s.strip != ''}
      .map{ |s| s.strip.gsub('<br>', '').squeeze(' ').gsub(' ,', ',').strip }

    # Fix Air Indiana Skydiving Center
    if loc_array[2] == "Delphi" && loc_array[3].start_with?("IN")
      loc_array[2] = loc_array[2] + ", " + loc_array[3]
      loc_array.delete_at(3)
    end

    # Fix Palatka
    loc_array[2] = 'Palatka FL, 32177' if loc_array[2] == 'Palatka FL, FL'
    # Fix Skydive Palm Beach
    loc_array[2] = 'Wellington, FL 33470' if loc_array[2] == 'Wellington, FL'
    # Fix Skydive Greater Michigan City
    loc_array[2] = 'Kankakee, IL 60901' if loc_array[2] == 'Kankakee, IL'
    # Fix Kansas State University Parachute Club
    if loc_array[0].include?('(K78)')
      loc_array.insert(1, '801 S Washington St')
      loc_array[2] = loc_array[2] + ' 67410'
    end
    # Fix Southern Minnesota Skydiving
    if loc_array.last == '55 miles S of Twin Cities'
      loc_array.insert(1, '35493 110th Street')
      loc_array[2] = loc_array[2] + ' 56093'
    end
    # Fix Jump Ohio
    # loc_array[2] = loc_array[2] + ' 44231' if loc_array[0].include?('(7D8)') && loc_array[2].start_with?('Parkman')
    # Fix Skydive Superior
    loc_array[3] = 'Superior, ' + loc_array[3] if loc_array[3] && loc_array[3].include?('54880')

    loc_array
  end

  # Gets the description of the dropzone
  def get_description(xml)
    desc = xml.to_s.gsub("\r\n", '').string_between_markers('<br><br>','<br><br><span class="title">LAT').split('<br><br>').last.strip.squeeze('  ').gsub('&acirc;&#128;&#153;', "'").gsub('&amp;','&')
    if desc.include?("Aircraft:")
      # That means that there's no description.
      ""
    elsif desc.include?("<br>")
      desc.gsub(/^.*>/, '').strip
    else
      desc
    end
  end

end

dzs = DZScraper.new

File.open("../dropzones-new.geojson","w") do |f|
  # f.write(dzs.scrape_local.to_json)
  f.write(dzs.scrape_online.to_json)
end
