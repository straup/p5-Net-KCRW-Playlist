use strict;

# $Id: Playlist.pm,v 1.6 2009/01/01 17:12:43 asc Exp $

package Net::KCRW::Playlist;
use base qw(LWP::UserAgent);

$Net::KCRW::Playlist::VERSION = '1.0';

=head1 NAME

Net::KCRW::Playlist - Fetch playlist data for the KCRW.org radio station

=head1 SYNOPSIS

 my $ymd = '20081230';
 my $start = undef;
 my $stop = '10 AM';

 my $kcrw = Net::KCRW::Playlist->new();
 my $songs = $kcrw->fetch($ymd, $start, $stop);

 print Dumper($songs);

 # which would print something like this:

 $VAR1 = [
          {
            'album' => 'Bajo Fondo',
            'artist' => 'Emilio Kauderer',
            'song' => 'Maroma (Fill)',
            'time' => '8:59'
          },
          {
            'album' => 'Popular (Unreleased)',
            'artist' => 'Van Hunt',
            'song' => 'Turn My Tv On',
            'time' => '9:04'
          },
          {
            'album' => 'Verve Unmixed 4 Verve',
            'artist' => 'Marlena Shaw',
            'song' => 'California Soul',
            'time' => '9:08'
          },
          ]

=head1 DESCRIPTION

Fetch playlist data for the KCRW.org radio station.

=cut

use utf8;
use Encode;

use HTML::TableExtract;
use Date::Parse;
use Date::Format;

use HTTP::Request;
use Digest::MD5 qw (md5_hex);
use URI::Escape;

=head1 PACKAGE METHODS

=cut

=head2 __PACKAGE__->new(%args)

Net::KCRW::Playlist subclasses the LWP::UserAgent package so anything you
can pass to the latter's contructor you may pass to the former.

Returns a I<Net::KCRW::Playlist> object!

=cut

=head1 OBJECT METHODS

=cut

=head2 $obj->fetch($ymd, $start, $stop)

=over 4

=item * B<$ymd> (required)

The year, month and day to fetch playlist information. Should be
formatted as a ISO-8601 compliant date (but can be formatted in
anything the I<Date::Parse> module understands).

=item * B<$start> (optional)

The minimum time of day in which to fetch playlist information. Can
be formatted in anything that the I<Date::Parse> understands.

=item * B<$stop> (optional)

The maximum time of day in which to fetch playlist information. Can
be formatted in anything that the I<Date::Parse> understands.

=back

Returns an array reference of tracks/songs, each a hash reference
containing the following keys: time, artist, song and album.

=cut

sub fetch {
        my $self = shift;
        my $ymd = shift;
        my $start = shift;
        my $stop = shift;

        #

        my $ts = str2time($ymd);
        my $ymd_short = time2str("%y%m%d", $ts);

        my $url = "http://legacy.kcrw.com:81/pl/" . $ymd_short . ".html";
        my $res = $self->get($url);

        if (! $res->is_success()){
                warn "failed to retrieve '$url', " . $res->message();
                return;
        }

        #

        my $min_date = undef;
        my $max_date = undef;

        if (defined($start)){
                $min_date = str2time("$ymd $start");
        }

        if (defined($stop)){
                $max_date = str2time("$ymd $stop");
        }

        #

        my $te = HTML::TableExtract->new(headers=>['TIME', 'ARTIST', 'SONG', 'ALBUM & LABEL INFO']); 
        $te->parse($res->content());

        my @songs = ();

        foreach my $row ($te->rows()){

                if ($row->[1] =~ /\[break\]/i){
                        next;
                }

                my @track = map {
                        $_ =~ s/\240/ /mg;
                        $_ =~ s/\n//gm;
                        $_ =~ s/(http\:.*)$//i;
                        $_ =~ s/(www\..*)$//i;
                        $_ =~ s/^\s//;
                        $_ =~ s/\s$//;
                        $_;
                } @{$row};

                my $ts = str2time("$ymd $track[0]:00");

                if ((defined($min_date)) || (defined($max_date))){

                        if ((defined($min_date)) && ($ts < $min_date)){
                                next;
                        }

                        if ((defined($max_date)) && ($ts > $max_date)){
                                next;
                        }
                }

                my $track_dt = time2str("%Y-%m-%d %H:%M:%S", $ts);

                push @songs, {'time' => encode('utf8', $track_dt),
                              'artist' => encode('utf8', $track[1]),
                              'song' => encode('utf8', $track[2]),
                              'album' => encode('utf8', $track[3])};
        }

        return \@songs;
}

=head2 $obj->assign_musicbrainz_ids(\@songs)

Iterate through a list of songs (returned by the I<fetch> method) and try
to assign a MusicBrainz track ID, release (album) ID and duration info.

At the moment, this method isn't very smart about trying to disambiguate
multiple track listings returned via the MusicBrainz API.

If successful, the keys assigned are: mb_track_id, mb_release_id and mb_duration.

Returns true or false.

=cut

# http://musicbrainz.org/doc/XMLWebService

sub assign_musicbrainz_ids {
        my $self = shift;
        my $songs = shift;

        eval "require XML::XPath";

        if ($@){
                warn "failed to XML::Path (skipping music brainz), $@";
                return 0;
        }

        foreach my $info (@$songs){

                my $url = "http://musicbrainz.org/ws/1/track/MBID/?type=xml";
                $url .= "&artist=" . uri_escape($info->{'artist'});
                $url .= "&title=" . uri_escape($info->{'song'});

                my $res = $self->get($url);

                if (! $res->is_success()){
                        next;
                }

                my $xml = undef;

                eval {
                        $xml = XML::XPath->new('xml' => $res->content());
                };

                if ($@){
                        warn "failed to parse response for '$url', $@";
                        next;
                }

                my @tracks = $xml->findnodes("/metadata/track-list/track");

                if (scalar(@tracks) == 1){
                        $info->{'mb_track_id'} = encode('utf8', $tracks[0]->getAttribute("id"));
                        $info->{'mb_release_id'} = encode('utf8', $tracks[0]->findvalue("release-list/release/\@id")->string_value());
                        $info->{'mb_duration'} = encode('utf8', $tracks[0]->findvalue("duration")->string_value());
                }

                else {

                        foreach my $tr (@tracks){
                                # print "$info->{'album'} : " . $tr->findvalue("release-list/release/title")->string_value() . "\n";
                        }
                }

                sleep(1);
        }

        return 1;
}

=head2 $obj->scrobble($lastfm_user, $lastfm_pswd, \@songs)

=cut

# http://www.last.fm/api/submissions
# to do: use version 1.2 of the submissions api

sub scrobble {
        my $self = shift;
        my $user = shift;
        my $pass = shift;
        my $songs = shift;

        $user = uri_escape($user);
        $pass = md5_hex($pass);

        my $url='http://post.audioscrobbler.com/?'.
                join('&',
                     'hs=true',
                     'p=1.1',
                     # http://www.last.fm/api/submissions#1.1
                     'c=tst',
                     'v=1.0',
                     'u=' . $user
                    );

        my $res = $self->get($url);

        if (! $res->is_success()){
                warn "handshake failed\n";
                return undef;
        }

        my @response = split(/[\r\n]+/, $res->content());

        if ($response[0] ne 'UPTODATE'){
                warn "invalid handshake";
                return undef;
        }

        my $challenge = $response[1];
        my $submit_url = $response[2];
        my $wait = $response[3];

        my $token = md5_hex($pass . $challenge);

        my $query = "u=$user&s=$token";
        my $i = 0;

        foreach my $info (@$songs){

                my %bits = ('a' => uri_escape($info->{'artist'}),
                            't' => uri_escape($info->{'song'}),
                            'b' => uri_escape($info->{'album'}),
                            'i' => uri_escape($info->{'time'}),
                            'm' => uri_escape($info->{'mb_track_id'}),
                            'l' => uri_escape($info->{'mb_duration'}),
                            'o' => 'R',
                           );

                map {
                        my $key = $_ . "[" . $i ."]";
                        my $value = $bits{$_};
                        $query .= "&$key=$value";
                } qw( a t b m l i);

                # Note: the order of events matter...

                $i ++;
        }

        print $query . "\n";

        my $post = HTTP::Request->new("POST", $submit_url);
        $post->content_type("application/x-www-form-urlencoded; charset=\"UTF\"");
        $post->content($query);

        my $res = $self->request($post);

        if (! $res->is_success()){
                warn "scrobbling failed, " . $res->message();
                return 0;
        }

        print "OK?\n";
        print $res->as_string();
        return 1;
}
=head1 VERSION

1.0

=head1 DATE

$Date: 2009/01/01 17:12:43 $

=head1 AUTHOR

Aaron Straup Cope E<lt>ascope@cpan.orgE<gt>

=head1 LICENSE

Copyright (c) 2008 Aaron Straup Cope. All Rights Reserved.

This is free software. You may redistribute it and/or
modify it under the same terms as Perl itself.

=cut

return 1;
