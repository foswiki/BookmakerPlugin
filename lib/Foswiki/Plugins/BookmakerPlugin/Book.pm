# See bottom of file for license and copyright information
package Foswiki::Plugins::BookmakerPlugin::Book;

=begin TML

---+ package Foswiki::Plugins::BookmakerPlugin::Book

An object that represents a loaded book topic. A book is simply a list of topics,
with some simple rules regarding its composition:
   1 It is ordered
   1 It stores full web.topic names
   1 Entries are unique (can occur only once)
   1 Indentation is used to indicate the topic "level"

Note that the methods of this class use =Foswiki::Func::normalizeWebTopicName= to
ensure canonical web.topic names. These calls use the BOOKMAKER_BOOKWEB preference
(which defaults to "Sandbox") as the default web.

=cut

use strict;
use warnings;
use Foswiki::Func ();
use Assert;

=begin TML

---++ ClassMethod new($topic)
   * =$topic= - name of the topic that will contain the book

Construct a new Book object by loading the topic specified by the $topic
(which should be a web.topic name)

If the topic already exists, access controls will be checked for read access. If this is
denied, an AccessControlException will be thrown.

Note that Foswiki macros in the topic are expanded when it is loaded, thus allowing
use of %INCLUDE etc. However these macros will be lost when the book is saved.

=cut

sub new {
    my ($class, $title) = @_;

    my ($web, $topic) = _canonicalise($title);
    my $this = bless({ web => $web, topic => $topic, order => [] }, $class);

    # load the table of contents topic
    if (Foswiki::Func::topicExists($web, $topic)) {
        my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
	throw Foswiki::AccessControlException(
	    "VIEW", $Foswiki::Plugins::SESSION->{user}, $web, $topic, "access denied")
	    unless Foswiki::Func::checkAccessPermission(
		"VIEW", Foswiki::Func::getWikiName(),
		$text, $topic, $web, $meta);

	# Expand any embedded macros. Note that this *destroys* the macros.
	$text = Foswiki::Func::expandCommonVariables(
	    $text, $topic, $web, $meta);

        # extract the list
        my @lines = grep { /^(\t|   )+(\*|\d+)\s/ } split( /[\n\r]+/, $text );
    
        # Check that each topic in the WebOrder only appears once
        my %seen;

        foreach my $line ( @lines ) {
	    next unless $line =~ /^((?:   |\t)+)(?:\*|\d+)\s*(.*?)\s*$/;
	    my ($indent, $name) = ($1, $2);
	    $indent =~ s/(   |\t)/./g;
        
            next if ($seen{$name});
            $seen{$name} = 1;

	    my ($web, $topic) = _canonicalise($name);

            push(@{$this->{order}}, { web => $web, topic => $topic, level => length($indent) - 1 });
        }
    }
    return $this;
}

# Private method to get a canonical web.topic name
sub _canonicalise {
    my $name = shift;
    return Foswiki::Func::normalizeWebTopicName(
	Foswiki::Func::getPreferencesValue('BOOKMAKER_BOOKWEB') || 'Sandbox', $name);
}

=begin TML

---++ ObjectMethod find($name) -> $index
Given the name of a topic (which must be a canonical web.topic name) return the index of that
topic in the book. Returns -1 if the topic is not found in the book.

Note that a topic can only occur once in a book.

=cut

sub find {
    my ($this, $name) = @_;
    my ($web, $topic) = _canonicalise($name);
    for (my $i = 0; $i < scalar(@{$this->{order}}); $i++) {
	return $i if ($this->{order}->[$i]->{web} eq $web &&
		      $this->{order}->[$i]->{topic} eq $topic);
    }
    return -1;
}

=begin TML

---++ ObjectMethod at($index) -> $entry
Get the entry at a given index, or undef if it is out of range.

The entry is a hash containing { topic, level }

=cut

sub at {
    my ($this, $i) = @_;
    return undef unless $i >= 0 && $i < scalar(@{$this->{order}});
    return $this->{order}->[$i];
}

=begin TML

---++ ObjectMethod remove($i) -> $entry
Remove the topic at the given index from the book.
If $i <0, will shift the first entry. If > length, will pop the last. Otherwise will splice.

Returns the removed entry.

=cut

sub remove {
    my ($this, $i) = @_;
    my $x;
    if ($i <= 0) {
	$x = shift(@{$this->{order}});
    } elsif ($i >= $#{$this->{order}}) {
	$x = pop(@{$this->{order}});
    } else {
	$x = $this->{order}->[$i];
	splice(@{$this->{order}}, $i, 1);
    }
    return $x;
}

=begin TML

---++ ObjectMethod add($entry) -> $entry
Add an existing entry to the end of the book.

---++ ObjectMethod add($name [, $level]) -> $entry
Create a new entry at the end of the book.

The topic will be added at level 0 if $level is not given.

Returns the new entry.

=cut

sub add {
    my $this = shift;
    return $this->insert(scalar(@{$this->{order}}), @_);
}

=begin TML

---++ ObjectMethod insert($i, $name [, $level]) -> $entry
Create a new entry at the given index. If $i <0, will add at the
start, if $i > length at the end,

The topic will be added at level 0 if $level is not given.

Returns the new entry.

---++ ObjectMethod insert($i, $entry) -> $entry
Insert an existing entry at the given index;

=cut

sub insert {
    my ($this, $i, $name, $level) = @_;
    my $e;
    if (ref($name)) {
	$e = $name;
    } else {
	my ($web, $topic) = _canonicalise($name);
	$e = { web => $web, topic => $topic, level => $level || 0 };
    }
    if ( $i >= 0 ) {
	if ($i < scalar(@{$this->{order}}) ) {
	    splice(@{$this->{order}}, $i, 0, $e);
	} else {
	    push(@{$this->{order}}, $e);
	}
    } else {
	unshift(@{$this->{order}}, $e);
    }
    return $e;
}

=begin TML

---++ ObjectMethod each() -> $iterator
Return an iterator over the topics in the book. Iterators are used as follows:
<verbatim>
my $i = $book->each();
while ($i->hasNext()) {
    my $entry = $i->next();
    # $entry is a hash with {web, topic, level}
}
</verbatim>
Modifying the list during iteration is *not* supported.

=cut

sub each {
    my ($this) = @_;
    require Foswiki::ListIterator;
    return Foswiki::ListIterator->new($this->{order});
}

=begin TML

---++ ObjectMethod save()

Save the current book to the book topic. The caller must have CHANGE access, or an
!AccessControlException will be thrown. Meta-data on any existing topic is retained.

=cut

sub save {
    my ($this) = @_;
    throw Foswiki::AccessControlException("CHANGE")
	unless Foswiki::Func::checkAccessPermission(
	    "CHANGE", Foswiki::Func::getWikiName(),
	    undef, $this->{topic}, $this->{web});
    my $m;
    if (Foswiki::Func::topicExists($this->{web}, $this->{topic})) {
	($m, my $t) = Foswiki::Func::readTopic($this->{web}, $this->{topic});
    }
    my $i = 0;
    my $list = join(
	"\n",
	map { ('   ' x ($_->{level} + 1)) . (++$i) . " $_->{web}.$_->{topic}" } @{$this->{order}})
	. "\n";
    Foswiki::Func::saveTopic($this->{web}, $this->{topic}, $m, $list, {
	ignorepermissions => 1,
	minor => 1,
	dontlog => 1 });
}

=begin TML

---++ ObjectMethod stringify() -> $string

Generate a string representation of the book, suitable for debugging.

=cut

sub stringify {
    my $this = shift;
    require Data::Dumper;
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Terse  = 1;
    return Data::Dumper->Dump( [$this] );
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2011 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
