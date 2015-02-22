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
require "set"
require_relative "utils"

if ARGV.size < 5
	puts "Paramaters: 'j2objc_path' 'j2objc_options' 'project_file' 'project_target_name' 'java_src_root::package' ..."
	exit
end

start_t = Time.now

def error_exit(message)
	unless message.nil? or message.empty?
		puts message
	end
	puts "FAILURE"
	exit
end

def filter(updated_text, type)
	return updated_text.split("\n").select{|f| f.start_with?("[" + type + "]")}.map{|f| f[6..-1]}.select{|f| !Utils.ignore?(f)}
end

def list_objc_files(dest_objc)
	p = Pathname.new(dest_objc.to_s)
	return p.directory? ? p.find.select{|f| !Utils.ignore?(f) and Utils.end_with?(f, Constants.objc_types)} : []
end

def resolve_res(file, dest_java, dest_res)
	p = Pathname.new(file)
	p_l = []
	p.each_filename do |filename|
		p_l << filename
	end
	d = Pathname.new(dest_res)
	d_l = []
	d.each_filename do |filename|
		d_l << filename
	end
	return Pathname.new(dest_res) + Pathname.new(file).relative_path_from((Pathname.new(dest_java) + p_l[d_l.size]).dirname).to_s
end

def list_files(obj)
	p = Pathname.new(obj)
	files = []
	if p.directory?
		p.children(true).each do |c|
			unless Utils.ignore?(c)
				files += list_files(c)
			end
		end
	else
		unless Utils.ignore?(p)
			files << p
		end
	end
	return files
end

def roll_back(dest_java_bkp, dest_java)
	if Pathname.new(dest_java_bkp).exist?
		file_count = Utils.count_files(dest_java_bkp)
		puts "Rolling back #{file_count} files..."
		%x(ruby sync_folder.rb '#{dest_java_bkp}' '#{dest_java}')
		Utils.delete(dest_java_bkp)
	else
		Utils.delete(dest_java)
	end
end

j2objc_path = ARGV[0] + "/j2objc"
j2objc_options = ARGV[1]
project_file = ARGV[2]
target_name = ARGV[3]

java_src_folders = []

i = 4
while !(ARGV[i].nil?) do
	java_src_folders << ARGV[i].split("::")
	i += 1
end

dest = Pathname.new(project_file).dirname.to_s + "/Java"
dest_java = dest + "/java"
dest_java_subs = []
java_src_folders.each_with_index do |folder, index|
	dest_java_subs << dest_java + "/src" + (index == 0 ? "" : ("-" + index.to_s))
end
dest_java_bkp = dest + "/java-bkp"
dest_objc = dest + "/objc"
dest_res = dest + "/res"

old_objc_files = list_objc_files(dest_objc)
old_objc_files_set = Set.new(old_objc_files)

all_files = []

java_src_folders.each do |src_folder|
	src = src_folder.first
	if Pathname.new(src).directory?
		all_files += list_files(src)
	else
		error_exit(src + " doesn't exist!")
	end
end

all_file_names = all_files.map{|f| Pathname.new(f).basename.to_s}
unless all_file_names.eql?(all_file_names.uniq)
	puts "The following files/classes needs to be renamed:"
	dups = []
	all_file_names.uniq.each do |file_name|
		fs = all_files.select{|f| Pathname.new(f).basename.to_s == file_name}
		if fs.size != 1
			dups += fs
		end
	end
	dups = dups.uniq.sort{|f1, f2| Pathname.new(f1).basename.to_s <=> Pathname.new(f2).basename.to_s}
	puts dups.map{|f| Pathname.new(f).basename.to_s + "\t " + Pathname.new(f).dirname.to_s}.delete_if{|f| f.strip.empty?}
	roll_back(dest_java_bkp, dest_java)
	error_exit("")
end

if Pathname.new(dest_java).exist?
	file_count = Utils.count_files(dest_java)
	puts "Backing up #{file_count} files..."
	%x(ruby sync_folder.rb '#{dest_java}' '#{dest_java_bkp}')
end

puts "Detecting updated files..."
updated = ""
java_src_folders.each_with_index do |src_folder, index|
	src = src_folder[0]
	package = src_folder[1]
	dest = dest_java_subs[index]
	updated += %x(ruby sync_folder.rb '#{src}' '#{dest}' '#{package}') + "\n"
end

translatable = filter(updated, "ADD") + filter(updated, "UPD")
removed = filter(updated, "REM")
updated_count = translatable.size + removed.size
puts (updated_count != 0 ? "#{updated_count} files updated." : "No files updated.")

unless translatable.empty? and removed.empty?
	j2objc_translatable = translatable.select{|f| Utils.java?(f)}
	unless j2objc_translatable.empty?
		j2objc_translatable_count = j2objc_translatable.size
		j2objc_translatable = j2objc_translatable.map{|f| "'" + f + "'"}.join(" ")
		puts "Translating #{j2objc_translatable_count} files..."
		sourcepath = dest_java_subs.join(":")
		unless system("#{j2objc_path} #{j2objc_options} -d '#{dest_objc}' -sourcepath '#{sourcepath}' #{j2objc_translatable}")
			puts "ERROR: j2objc translation failed. Stopping."
			roll_back(dest_java_bkp, dest_java)
			error_exit("")
		end
	end
	resources = translatable.select{|f| !Utils.java?(f)}
	unless resources.empty?
		puts "Adding #{resources.size} resource files..."		
		resources.each do |f|
			src_p = Pathname.new(f)
			dest_p = resolve_res(f, dest_java, dest_res)
			Utils.cp(src_p, dest_p)
		end
	end
	unless removed.empty?
		puts "Removing #{removed.size} files..."		
		new_objc_files = list_objc_files(dest_objc)
		new_objc_files_set = Set.new(new_objc_files)
		removed.each do |f|
			if Utils.java?(f)
				fns = Constants.objc_types.map{|ext| Pathname.new(f).basename.to_s[0..-6] + ext}
				files = new_objc_files.select{|new_objc_file| fns.any?{|fn| fn == new_objc_file.basename.to_s}}
				files_set = Set.new(files)
				obs_fs = (files_set - (new_objc_files_set - old_objc_files_set))
				if obs_fs.size == 2
					obs_fs.each do |file|
						Utils.delete(file)
					end
				else
					puts "File ambiguity! Delete the following files manually: #{fns[0]}, #{fns[1]}"
				end
			end
			if Utils.end_with?(f, Constants.resource_types)
				Utils.delete(resolve_res(f, dest_java, dest_res))
			end
		end
	end
	puts "Cleaning up..."		
	Utils.clean_up(dest)
	puts "Updating Xcode project..."
	%x(ruby sync_xcode.rb '#{project_file}' '#{target_name}' 'Java/objc')
	%x(ruby sync_xcode.rb '#{project_file}' '#{target_name}' 'Java/res')
end

if Pathname.new(dest_java_bkp).exist?
	Utils.delete(dest_java_bkp)
end

finish_t = Time.now
delta = finish_t.to_i - start_t.to_i
time_s = delta < 60 ? "#{delta} seconds" : "#{((delta/10).round)/6} minutes"

puts "Processing took #{time_s}."
puts "SUCCESS"
