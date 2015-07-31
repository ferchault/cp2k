#!/usr/bin/env python

import argparse
import struct
import sys

parser = argparse.ArgumentParser('Converts CP2K cube files with binary voxel data to standard cube files.')
parser.add_argument('infile', type=argparse.FileType('r'), help='Input cube file.')
parser.add_argument('outfile', type=argparse.FileType('w'), help='Output cube file.')
mode = parser.add_mutually_exclusive_group(required=False)
mode.add_argument('--exact_match', action='store_true', help='Exactly match the CP2K non-binary output format.')
mode.add_argument('--max_precision', action='store_true', help='Print as many digits as there are significant digits in the binary input.')

def _get_header(infile):
	""" Reads the meta data for the binary segment from the cube file. 

	Returns tuple of 
	 - memory width per value
	 - number of values per newline-separated line
	 - number of bytes to skip until the binary file section
	 - the original cube file header
	 - number of voxel along the third axis"""

	#: memory in bytes for a single value
	width = None
	#: number of values in a given line
	count = None
	#: characters to skip until the binary part of the cube file
	skip = 0
	#: lines belonging to the cube file header
	lines = []
	while width is None:
		line = next(infile)
		skip += len(line)
		if line.startswith('BINARYVOXEL'):
			width, count = map(int, line.split()[-2:])
			break
		
		lines.append(line)

	#: number of voxel along the third axis
	zvoxel = int(lines[5].split()[0])

	return width, count, skip, lines, zvoxel

def _format_fortran(value):
	"""Converts a float to fortran-style scientific notation.

	The only difference here is that the first digit in fortran notation always is a zero."""
	base = '% .4E' % (value*10)
	base = '%s0.%s%s%s' % (base[0],base[1], base[3:7], base[-4:])
	return base

def _representation(element, match, max_precision, significant_digits):
	if not match and not max_precision:
		# python scientific notation -1.2345E+00
		return '% .4E' % element
	elif match:
		# fortran scientific notation -0.12345E+00
		return _format_fortran(element)
	elif max_precision:
		# python scientific notation with as many significant digits as possible
		format = '%% .%dE' % (significant_digits-1)
		return format % element

def _nextlinecount(read_values, cachelen, count, zvoxel, match):
	"""Calculated the expected number of elements in the next output file line given the current cache state.

	Parameters:
	read_values: Total amount of values read from input file.
	cachelen:    Number of string representations to write to output file.
	count:       Columns of the output file
	zvoxel:      Number of grid points along the third axis of the cube file.
	match:       Whether to reproduce CP2K own cube file printing."""

	# calculate the number of elements in the _next_ line 
	nextlinecount = 0
	#: number of values in the minimum cycle that completes a whole output line
	cyclelen = 0
	if match:
		# CP2K default output gives a line break after each third axis loop
		cyclelen = zvoxel
	else:
		cyclelen = count

	pos = (read_values-cachelen) % cyclelen
	nextlinecount = count
	if match:
		lastlinecount = cyclelen % count
		if pos >= cyclelen-lastlinecount:
			# in last line
			nextlinecount = lastlinecount

	return nextlinecount

def _convert(infile, outfile, width, count, zvoxel, match=False, max_precision=False):
	cache = []
	first_line = True

	significant_digits = 7 # single precision
	if width == 4:
		significant_digits = 7 # single
	if width == 8:
		significant_digits = 15 # double
	if width >= 16:
		significant_digits = 34 # quad
	
	read_values = 0
	while True:
		# support incomplete lines if the voxel count along the last axis is not an integer multiple of "count"
		my_count = min(count, zvoxel-(read_values % zvoxel))
		read_values += my_count

		chunk = infile.read(width*my_count)
		if len(chunk) == 0:
			break
		try:
			this_values = list(struct.unpack('%df' % ((width/4)*my_count), chunk))
		except:
			print 'Invalid file. Expected %d characters in line, got %d.' % ((width/4)*my_count, len(chunk))
			exit(1)
		infile.read(1) # skip newline
		
		# format voxel 
		for element in this_values:
			cache.append(_representation(element, match, max_precision, significant_digits))

		# print voxel
		while True:
			nextlinecount = _nextlinecount(read_values, len(cache), count, zvoxel, match)
			if nextlinecount > len(cache):
				break

			if match:
				outfile.write(' ')
			outfile.write(' '.join(cache[:nextlinecount]))
			outfile.write('\n')
			cache = cache[nextlinecount:]
	if len(cache) > 0:
		outfile.write(' '.join(cache))
		outfile.write('\n')

def main(args):
	width, count, skip, lines, zvoxel = _get_header(args.infile)
	if width % 4 != 0:
		print 'Value memory size has to be a integer multiple of 32 bit. Got %d.' % width

	args.infile.seek(skip, 0)

	for line in lines:
		args.outfile.write(line)

	_convert(args.infile, args.outfile, width, count, zvoxel, args.exact_match, args.max_precision)

if __name__ == '__main__':
	args = parser.parse_args()
	main(args)