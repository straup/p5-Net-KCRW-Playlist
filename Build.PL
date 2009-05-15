# $Id: Build.PL,v 1.1 2009/05/13 14:55:43 asc Exp $

use strict;
use Module::Build;

my $build = Module::Build->new(module_name => 'Net::KCRW::Playlist',
			       # dist_author
			       # dist_abstract
			       dist_version_from => 'lib/Net/KCRW/Playlist.pm',
			       license           => 'perl',
			       requires => {
                                            'LWP::UserAgent' => '0',
                                            'Date::Parse' => '0',
                                            'Date::Format' => '0',
                                            'HTML::TableExtract' => '0',
			       },
			       build_requires => {
				   'Test::Simple'              => '>= 0.47',
			       },
			       create_readme      => 1,
			       create_makefile_pl => 'passthrough');

$build->create_build_script();
