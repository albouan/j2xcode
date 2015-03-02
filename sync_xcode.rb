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
require "xcodeproj"
require "pathname"
require_relative "utils" 

if ARGV.size < 3
	puts "Usage: sync_xcode project_file target_name sources_rel_folder"
	exit
end

project_file = ARGV[0]
target_name = ARGV[1]
sources_name = ARGV[2]

project_file_p = Pathname.new(project_file)
project_folder_p = project_file_p.dirname
target_folder_p = Pathname.new("/" + sources_name)

def scan(root_p, path_p, filter_s, list)
  path_p.children.collect do |child|
    if child.file?
      p = Pathname.new("/") + child.relative_path_from(root_p).to_s
      if !Utils.ignore?(p) and p.to_s.start_with?(filter_s)
      	list << p
      end
    elsif child.directory?
      scan(root_p, child, filter_s, list)
    end
  end.select{|x| x}.flatten(1)
end

def find_phase(project, target_name, cls)
	phases = project.targets.select{|t| t.name == target_name}.first.build_phases.select{|p| p.instance_of? cls}
	if phases.size > 1
		puts "WARNING: multiple #{cls.to_s}, using first"
	end
	return phases.first
end

def find_group(project, file_p)
	c_group = project
	file_p.to_s.split("/").each do |filename|
		index = c_group.groups.index{|g| g.name == filename}
		unless index.nil?
	 		c_group = c_group.groups[index]
	 	end	
	end 
	return c_group
end

def empty?(group)
	if group.files.empty?
		if group.groups.empty?
			return true
		else
			group.groups.each do |g|
				unless empty?(g)
					return false
				end
				return true
			end
		end
	else
		return false
	end
end

files_p = []

scan(project_folder_p, project_folder_p, target_folder_p.to_s, files_p)

project = Xcodeproj::Project.open(project_file_p.to_s)

project_files_p = []
project_files_refs = []

project.files.each do |file|
	file_p = Pathname.new(file.hierarchy_path)
	if file_p.to_s.start_with?(target_folder_p.to_s)
		project_files_p << file_p
		project_files_refs << file
	end
end

compile_phase = find_phase(project, target_name, Xcodeproj::Project::Object::PBXSourcesBuildPhase)
resources_phase = find_phase(project, target_name, Xcodeproj::Project::Object::PBXResourcesBuildPhase)
copy_files_phase = find_phase(project, target_name, Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)

modified = false

project_files_p.each_with_index do |file_p, index|
	if files_p.index{|f| f.to_s == file_p.to_s}.nil?
		ref = project_files_refs[index]
		group = find_group(project, ref.hierarchy_path)
		compile_phase.files.delete_if{|b| b.file_ref == ref}
		compile_phase.files_references.delete(ref)
		unless resources_phase.nil?
			resources_phase.files.delete_if{|b| b.file_ref == ref}
			resources_phase.files_references.delete(ref)
		else
			copy_files_phase.files.delete_if{|b| b.file_ref == ref}
			copy_files_phase.files_references.delete(ref)			
		end
		ref.remove_from_project
		while !group.nil? and empty?(group) do
			p_group = group.parent
			unless p_group.nil?
				p_group.children.delete(group)
			end
			group = p_group
		end
		modified = true
	end
end

req_groups_s = []

files_p.each do |file_p|
	c_path = ""
	file_p.dirname.each_filename {|filename| c_path += "/" + filename; req_groups_s << c_path}
end

req_groups_s = req_groups_s.uniq.sort

req_groups_s.each do |group_s|
	c_group = project	
	group_s.split("/").drop(1).each do |filename|
		index = c_group.groups.index{|g| g.name == filename}
		if index.nil?
			c_group = c_group.new_group(filename)
			modified = true
		else		
			c_group = c_group.groups[index]	
		end
	end
end

(files_p - project_files_p).each do |file_p|
	c_group = find_group(project, file_p)
	path = (project_folder_p + file_p.to_s[1..-1]).to_s
	if c_group.files.index{|f| f.path == path}.nil?
		ref = Xcodeproj::Project::Object::FileReferencesFactory.new_reference(c_group, path, "<absolute>")
		ref.name = file_p.basename.to_s
		project.files << ref
		unless Utils.end_with?(ref.name, Constants.header_types + Constants.resource_types) 
			compile_phase.add_file_reference(ref)
		end
		unless resources_phase.nil?
			if Utils.end_with?(ref.name, Constants.resource_types) 
				resources_phase.add_file_reference(ref)
			end
		else
			if Utils.end_with?(ref.name, Constants.header_types) 
				copy_files_phase.add_file_reference(ref)
			end			
		end
		modified = true
	end
end

if modified
	project.save(project_file_p)
	puts "Updated #{sources_name} contents."
else
	puts "No update necessary for #{sources_name}."
end