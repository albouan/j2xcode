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

require "pathname"
require "fileutils"

module Constants
	def self.objc_types
	[
		".h", 
		".m"
	]
	end
	
	def self.header_types
	 [
		".h",
		".hh",
		".hpp"
	]
	end

	def self.resource_types 
	[
		".html",
		".htm",
		".js",
		".css",
		".txt",
		".properties",
		".xml",
		".gif",
		".png",
		".jpeg",
		".jpg",
		".dtd",
		".tld"
	]
	end
	
	def self.ignored_files
	[
		"package.html",
		"package-info.java"
	]
	end
end

module Utils
	def self.ignore?(file)
		return (Pathname.new(file.to_s).basename.to_s.start_with?(".") or Constants.ignored_files.any?{|f| f == Pathname.new(file.to_s).basename.to_s})
	end

	def self.java?(file)
		return file.to_s.downcase.end_with?(".java")
	end

	def self.end_with?(file, exts_a)
		return exts_a.map{|e| file.to_s.downcase.end_with?(e)}.any?{|b| b}
	end
	
	def self.cp(src, dest)
		d = Pathname.new(dest.to_s)
		FileUtils.mkdir_p(d.dirname.to_s)
		FileUtils.cp(src.to_s, d.to_s)
	end
	
	def self.mkdir(dir)
		FileUtils.mkdir_p(dir.to_s)
	end

	def self.delete(obj)
		p = Pathname.new(obj.to_s)
		if p.exist?
			if p.directory?
				FileUtils.remove_dir(p.to_s, true)
			else
				p.delete
			end
		end
		return p
	end

	def self.clean_up(dir)
		p = Pathname.new(dir.to_s)
		if p.directory?
			p.children(true).each do |c|
				if c.directory?
					clean_up(c)
				end
			end
			if p.children(true).delete_if{|c| ignore?(c)}.empty?
				delete(p)
			end
		end
		return p		
	end

	def self.count_files(dir)
		n = 0
		p = Pathname.new(dir.to_s)
		if p.exist?
			if p.directory?
				p.children(true).each do |c|
					n += count_files(c)
				end
			else
				n += 1
			end
		end
		return n		
	end
	
	def self.cmp(file1, file2)
		return FileUtils.compare_file(file1, file2)
	end
end