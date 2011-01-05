#!/usr/bin/env perl 
#===============================================================================
#
#         FILE:  drupal_to_mt.pl
#
#        USAGE:  ./drupal_to_mt.pl --db=dbi:mysql:db_name --user=u --pass=p
#
#  DESCRIPTION:  Dump Drupal nodes to an Movable Type compatible import file
#                This was build for Drupal 4.x; YMMV with newer versions.
#       AUTHOR:  Phillip Smith (ps at phillipadsmith dot com),
#      VERSION:  1.0
#      CREATED:  01/04/2011 16:23:39
#===============================================================================

use strict;
use warnings;
use autodie;
use Modern::Perl;
use Data::Dump qw(dump ddx);
use DateTime;
use DBI;
use Getopt::Long;
use Pod::Usage;
use Template;
use Text::Markdown 'markdown';

my $man  = 0;
my $help = 0;
my $dsn;
my $db_user;
my $db_pass;

GetOptions(
    'help|?' => \$help,
    man      => \$man,
    'db=s'   => \$dsn,
    'user=s' => \$db_user,
    'pass=s' => \$db_pass,
) or pod2usage( 2 );
pod2usage( 1 ) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

if ( $dsn and $db_user and $db_pass ) {
    my $dbh = _connect_to_db( $dsn, $db_user, $db_pass );
    my $nodes = main( $dbh );    # Save # of nodes for testing
    $dbh->disconnect;
}

#---------------------------------------------------------------------------
#  Main subroutine that does the work
#---------------------------------------------------------------------------
sub main {
    my ( $dbh ) = @_;
    my @nodes = _get_nodes_from_db( $dbh );
    my %vars = ( nodes => \@nodes );
    my $tt = Template->new;
    $tt->process( \*DATA, \%vars );
    return scalar @nodes;
}    # ----------  end of subroutine main  ----------


#---------------------------------------------------------------------------
#  Helper subroutines
#---------------------------------------------------------------------------
sub _get_nodes_from_db {
    my ( $dbh ) = @_;
    my @nodes;
    my $statement = <<'END';
SELECT node.nid, 
	node_revisions.title, 
	node_revisions.body, 
	node_revisions.teaser, 
	node_revisions.format, 
	node.created
FROM node, node_revisions
WHERE node.vid = node_revisions.vid
AND
node.type = 'story'
END
    my $sth = _execute_statement( $dbh, $statement );
    while ( my @row = $sth->fetchrow_array ) {
        my %node = _build_node_object( $dbh, @row );
        push @nodes, \%node;
    }

    return @nodes;
}    # ----------  end of subroutine _get_nodes_from_db  ----------

sub _build_node_object {
    my ( $dbh, $nid, $title, $body, $teas, $format, $created ) = @_;
    my @tags           = _get_tags_by_nid( $dbh, $nid );
    my $category       = shift @tags;
    my $tags_as_string = join ', ', map {qq/"$_"/} @tags;
    my %data           = (
        nid     => $nid,
        title   => $title,
        body    => do { $format = 5 ? $body = markdown( $body ) : $body },
        teaser  => do { $format = 5 ? $teas = markdown( $teas ) : $teas },
        format  => $format,
        created => _return_mt_date( $created ),
        comments => _get_comments_by_nid( $dbh, $nid ),
        category => $category,
        tags     => $tags_as_string,
    );
    return %data;
}    # ----------  end of subroutine _build_node_object  ----------

sub _build_comment_object {
    my ($dbh,    $cid,  $subject, $comment, $created,
        $format, $name, $mail,    $homepage
    ) = @_;
    my %data = (
        cid      => $cid,
        subject  => $subject,
        comment  => $comment,
        created  => _return_mt_date( $created ),
        format   => $format,
        name     => $name,
        mail     => $mail,
        homepage => $homepage,
    );
    return %data;
}    # ----------  end of subroutine _build_comment_object  ----------

sub _get_comments_by_nid {
    my ( $dbh, $nid ) = @_;
    my @comments;
    my $statement = <<'END';
SELECT comments.cid, 
	comments.subject, 
	comments.comment, 
	comments.timestamp, 
	comments.format, 
	comments.name, 
	comments.mail, 
	comments.homepage
FROM comments
WHERE nid = ?
AND comments.status = '0'
ORDER BY comments.cid ASC
END
    my $sth = _execute_statement( $dbh, $statement, $nid );
    while ( my @row = $sth->fetchrow_array ) {
        my %comment = _build_comment_object( $dbh, @row );
        push @comments, \%comment;
    }
    return \@comments;
} # ----------  end of subroutine _get_comments_from_db_by_node  ----------

sub _get_tags_by_nid {
    my ( $dbh, $nid ) = @_;
    my @tags;
    my $statement = <<'END';
SELECT name from term_node n, term_data d where n.nid = ? and n.tid = d.tid
END
    my $sth = _execute_statement( $dbh, $statement, $nid );
    while ( my @row = $sth->fetchrow_array ) {
        my $tag = shift @row;
        push @tags, $tag;
    }
    return @tags;
}    # ----------  end of subroutine _get_tags_by_nid  ----------

sub _return_mt_date {
    my ( $epoch ) = @_;
    my $dt = DateTime->from_epoch( epoch => $epoch );
    my $date = $dt->mdy( "/" ) . " " . $dt->hms;    #  01/31/2002 15:47:06
    return $date;
}    # ----------  end of subroutine _return_mt_date  ----------

sub _connect_to_db {
    my ( $dsn, $user, $password ) = @_;
    my $dbh = DBI->connect( $dsn, $user, $password,
        { RaiseError => 1, AutoCommit => 0 } );
    return $dbh;
}    # ----------  end of subroutine _connect_to_db  ----------

#---------------------------------------------------------------------------
#  Provide the handle, statement, and the bind paramaters as an array
#---------------------------------------------------------------------------
sub _execute_statement {
    my ( $dbh, $statement, @bind_params ) = @_;
    my $sth = $dbh->prepare( $statement );
    if ( @bind_params ) {
        my $count = 1;
        foreach my $param ( @bind_params ) {
            $sth->bind_param( $count, $param );
            $count++;
        }
    }
    $sth->execute;
    return $sth;
}    # ----------  end of subroutine _execute_statement  ----------

=pod

=head1 NAME

Drupal to MovableType migration helper. 

=head1 SYNOPSIS

./drupal_to_mt.pl [options] > [file]

Options:
  -help            brief help message
  -man             full documentation
  -user            database username
  -pass            database password
  -db              dbi:Driver:databasename

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

This script will output a MovableType-compatible import file
from a Drupal (4.x) database. 

You'll need to adjust the statements if you want something different.

=cut

__END__
[% FOREACH node = nodes -%]
TITLE: [% node.title %]
AUTHOR:
DATE: [% node.created %]
PRIMARY CATEGORY: Archive
CATEGORY: [% node.category %] 
TAGS: [% node.tags %]
-----
BODY:
[% node.body %]
-----
EXCERPT:
[% node.teaser %]
-----
STATUS: draft
-----
ALLOW COMMENTS: 1
-----
[% FOREACH comment = node.comments -%]
COMMENT:
AUTHOR: [% comment.name %] 
EMAIL:  [% comment.mail %]
URL: [% comment.homepage %]
DATE: [% comment.created %] 
<strong>[% comment.subject %]</strong>
[% comment.comment %]
-----
[% END %]
--------
[% END %]
