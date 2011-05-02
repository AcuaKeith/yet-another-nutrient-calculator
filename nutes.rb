#!/usr/bin/env ruby

# this here dirty script was written by wet@petalphile.com
# for fellow aquatic plant nerds.  As long as you keep 
# this notice you can do what you want with it.  But 
# if you have ideas or make it better, please let me 
# know.  I'll probably want to help, like to learn,
# and like new ideas.
#
# :) - c

require 'rubygems'
require 'sinatra'
require 'haml'
require 'yaml'
require 'rdiscount'
require 'thin'

set :environment, :production 
#set :port, '4000'
set :bind, 'localhost'

# the constants array is every compound we support
constants = YAML.load_file 'constants/compounds.yml'
COMPOUNDS =  constants.keys.sort

get '/' do
	haml :ask
end
 
post '/' do
  cons 			= Hash.new
  @results		= Hash.new

# the Stuff while trying to limit what's global
  @tank_vol		= Float(params["tank_vol"]) || 0
  @tank_units		= params["tank_units"]
  @comp 		= params["compound"]
  @dose_method		= params["method"]
    
  @dose_units		= params["dose_units"]
  calc_for		= params["calc_for"]

# i just need this later
  @tank_vol_orig=@tank_vol
  

  if (@tank_units =~ /gal/)
    @tank_vol = @tank_vol * 3.78541178
    @tank_vol = Float(@tank_vol)
  end

# we'll populate everything from the constants hash we created earlier
  pop=constants[@comp]
  pop.each do |junk,value|
    if (junk =~ /tsp/)
      tsp_con = Float("#{value}")
    elsif (junk =~ /sol/)
      @solubility = value
    elsif (junk =~ /target/)
      @element = value
    else
      cons["#{junk}"]=Float("#{value}")
    end
  end

# is dose amount a fraction?


# calculations on the onClick optional menu
  if (calc_for =~ /dump/)
    @dose_amount	= params["dose_amount"]
    if (@dose_amount =~ /^(\d+)\/(\d+)$/)
	num = $1.to_f
	den = $2.to_f
	@dose_amount = num / den
    end
    @dose_amount = @dose_amount.to_f
  elsif (calc_for =~ /target/)
    @target_amount 	= Float(params["target_amount"])
    @dose_amount	= 0
  end	

  if (@dose_method =~ /sol/)
    @sol_vol		= Float(params["sol_volume"])
    @sol_dose		= Float(params["sol_dose"]) 
    dose_calc 		= @dose_amount * @sol_dose / @sol_vol
  else
    @sol_vol 		= 0
    @sol_dose		= 0
    dose_calc 		= @dose_amount
  end

#convert from tsp to mg
  if (@dose_units =~ /tsp/)
    dose_calc *= constants[@comp]['tsp']
    sol_check = @dose_amount * constants[@comp]['tsp']
  elsif (@dose_units =~ /^g$/)
    dose_calc *= 1000
    sol_check = @dose_amount * 1000
  else
    sol_check = 0
  end


#two forms

  if (calc_for =~ /dump/)
    cons.each do |con,value|
      pie="#{value}"
      pie=pie.to_f
      @results["#{con}"] = dose_calc * pie / @tank_vol
      @results["#{con}"] = sprintf("%.2f", @results["#{con}"])
    end
    @target_amount = @results["#{@element}"]
    @mydose=@dose_amount
  
  elsif (calc_for =~ /target/)
    pie=Float(cons["#{@element}"])
    @mydose = @target_amount * @tank_vol / pie
    @mydose = sprintf("%.2f", @mydose)
    @mydose = Float(@mydose)
    if (@dose_method=~ /sol/ && calc_for =~ /target/)
      @dose_amount = @mydose * @sol_vol / @sol_dose
      sol_check    = @dose_amount
    else
      @dose_amount = @mydose
    end
    cons.each do |conc,values|
      pie="#{values}"
      pie=pie.to_f
      @results["#{conc}"] = @mydose * pie / @tank_vol
      @results["#{conc}"] = sprintf("%.2f", @results["#{conc}"])
    end
    @dose_amount = @dose_amount / 1000
    @dose_units = 'grams'
  end

#check solubility
  if (constants[@comp]['sol'] && (@sol_vol > 1))
    sol_ref = constants[@comp]['sol'] * 0.8
    sol_check = sol_check / @sol_vol
    if ( sol_ref <  sol_check )
	@sol_error = "<font color='red'>#{@comp}'s solubility at room temperature<br>is #{constants[@comp]['sol']} mg/mL.<br>You should adjust your dose.</font><br>"
    end
  end

#K3PO4 is tricky
  if (@comp =~ /K3PO4/ )
	@toxic="K3PO4 in solution tends to raise pH due to<br/>
the nature of KOH, a strong base. <br/>
ray-the-pilot explains this for us gardeners here:<br/>
<a href='http://bit.ly/ev7txA'>'K3PO4 instead of KH2PO4?' at Aquatic Plant Central'</a></br>"
  end
  
#copper toxicity
  if (constants[@comp]['Cu'])
    if(@results['Cu'].to_f > 0.072)
	toxic = ( @results['Cu'].to_f - 0.072 ) / 0.072 
	less_dose = @dose_amount - ( @dose_amount * 0.072 / @results['Cu'].to_f )
	if (@dose_amount =~ /\./)
		less_dose = less_dose.round_to(3)
	else
		less_dose = less_dose.to_i
	end
	percent_toxic = (toxic * 100).to_i
	@toxic = "<font color='red'>Your Cu dose is #{percent_toxic}% more than recommended<br />for sensitive fish and inverts. Consider<br />reducing your #{@comp} dose by #{less_dose} #{@dose_units}.</font><br /><a href='/cu' target='_blank'>Read more about Cu toxicity here</a>.<br />"
    end
  end

# EDDHA tints the water red  
  if (@comp =~ /EDDHA/)
	if (@results['Fe'].to_f > 0.002)
		@toxic = "<font color='red'>Be aware that EDDHA will tint the water pink to red<br /> at even moderate doses.</font><br />You can check out a video of a 0.2ppm dose <a href='http://www.youtube.com/watch?v=ZCTu8ClcMKc' target='_blank'>here</a>.<br />"
	end
  end

# fancy graphs -- we're showing ranges recommended by various well regarded methods
#   vs what we just calculated.

# this yml file has The Estimative Index, PPS-Pro, and Walstad recommended values
  @range = YAML.load_file 'constants/dosingmethods.yml'

# if the data is smaller than our largest range above...
  unless ( @range["#{@element}"]["EI"]["high"] )
	@range["#{@element}"]["EI"]["high"] = 0
  end
  if ( ( @results["#{@element}"].to_f ) <  ( @range["#{@element}"]["EI"]["high"].to_f ) )

# we know the div will be 300 pixels wide.  So, let's get an amount for pixel per ppm
    pie=Float(@range["#{@element}"]["EI"]["high"])
  else
    pie=Float(@results["#{@element}"])
  end
# this will be our ppm at the highest pixel
  @pixel_max=pie * 1.25
  @pixel_per_ppm=300/@pixel_max
# and convert the pixel/ppm to integers so our graph does not break
  if @pixel_max > 1
  	@pixel_max=@pixel_max.to_int
  else
	@pixel_max=100 * @pixel_max.to_f / 100
  end
  
# we convert everything in our range from ppm to pixels, standardized off that ppm/pixel
  @range.each do |compound,method|
	method.each do |specific,value|
		value.each do |wtf,realvalue|
   			value[wtf]=realvalue.to_f * @pixel_per_ppm
			value[wtf]=value[wtf].to_int
			if ( value[wtf] < 4 )
				value[wtf] = 3
			end
   		end
	end
  end 
  @results_pixel=@results["#{@element}"].to_f * @pixel_per_ppm
  @results_pixel=@results_pixel.to_int
  
# and we finally display all of it.
  if (calc_for =~ /dump/)
  	haml :dump
  else
        haml :target
  end  

end

get '/cu' do
  markdown :cu
end

error do
  ':('
end

__END__
 