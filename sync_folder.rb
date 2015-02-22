#    J2Xcode: Ruby script to synchronize Java sources with Xcode using j2objc tool
#    Copyright (C) 2015, NG-Computing
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

require "rubygems"
require "pathname"
require_relative "utils"

if ARGV.size < 2
	puts "Usage: sync_folder src_folder dest_folder [package_filter]"
	exit
end

src = Pathname.new(ARGV[0])
dest = Pathname.new(ARGV[1])
dest_file = nil
dest_package = []
unless ARGV[2].nil?
	p3 = ARGV[2]
	if Utils.java?(p3)
		pn = Pathname.new(p3)
		p3 = pn.dirname.to_s
		dest_file = pn.basename.to_s
	end
	dest_package = p3.split(/\/|\./).delete_if{|p| p.empty?}
end
dest_package << '*'

updated_l = []

def add(src_p, dest_p, updated_l)
	unless Utils.ignore?(src_p)
		if dest_p.file?
			unless Utils.cmp(src_p, dest_p)
				Utils.cp(src_p, dest_p)
				updated_l << "[UPD] " + dest_p.to_s
			end
		else
			Utils.cp(src_p, dest_p)
			updated_l << "[ADD] " + dest_p.to_s
		end
	end
end

def rem(dest_p, updated_l, keep_l = [])
	dest_cs = dest_p.children(true)
	dest_cs.each do |dc|
		unless Utils.ignore?(dc)
			if dc.directory?
				rem(dc, updated_l, keep_l)
			else
				unless keep_l.any?{|f| f.to_s == dc.to_s}
					updated_l << "[REM] " + dc.to_s
					Utils.delete(dc)
				end
			end
		else
			Utils.delete(dc)
		end		
	end	
	Utils.clean_up(dest_p)
end

def sync(src_p, dest_p, dest_p_f, updated_l)
	if src_p.directory?
		src_cs = src_p.children(true)
		dest_cs = dest_p.directory? ? dest_p.children(true) : []
		dest_cs.each do |dc|
			unless Utils.ignore?(dc)
				if dc.directory?
					unless (src_p + dc.basename).directory? and (dest_p_f.first == '*' or dest_p_f.first == dc.basename.to_s)
						rem(dc, updated_l)
					end
				else
					unless (src_p + dc.basename).file?
						Utils.delete(dc)
						updated_l << "[REM] " + dc.to_s
					end
				end
			else
				Utils.delete(dc)
			end
		end
		src_cs.each do |sc|
			unless Utils.ignore?(sc)
				if dest_p_f.first == '*' or dest_p_f.first == sc.basename.to_s
					d = dest_p + sc.basename
					if sc.directory? and !d.directory?
						Utils.mkdir(d)
					end
					sync(sc, d, dest_p_f.first == '*' ? dest_p_f : dest_p_f.drop(1), updated_l)
				end
			end
		end
	else
		add(src_p, dest_p, updated_l)
	end
end

Utils.mkdir(dest)

if dest_file.nil?
	sync(src, dest, dest_package, updated_l)
else
	file_path = dest_package.take(dest_package.size - 1).join("/") + "/" + dest_file
	src_path = src + file_path
	dest_path = dest + file_path
	if src_path.file?
		if dest_path.file?
			unless Utils.cmp(src_path, dest_path)
				Utils.cp(src_path, dest_path)
				updated_l << "[UPD] " + dest_path.to_s
			end
			keep_l = []
			keep_l << dest_path.to_s
			rem(dest, updated_l, keep_l)
		else
			rem(dest, updated_l)
			add(src_path, dest_path, updated_l)
		end
	else
		rem(dest, updated_l)
	end	
end

puts updated_l