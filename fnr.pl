#!/usr/bin/perl 

use strict;
use warnings;
use WWW::Mechanize;
use HTML::TableExtract;
use Data::TreeDumper;
use Smart::Comments;

my $url = 'http://www.funddj.com/y/yb/YP303000.djhtm';
#my $url = 'http://www.funddj.com/y/yb/YP303001.djhtm';

my $mech = WWW::Mechanize->new;
$mech->get($url);
my @company_links = grep { $_->url_abs =~ /yp020000/ } $mech->links;

my %data;

foreach my $company_link (@company_links) {
	my $company_name = $company_link->text;
	print STDERR "$company_name\n";
	my $company_url  = $company_link->url_abs;
	$mech->get($company_url);
	
	my @fund_links = grep { $_->url_abs =~ /yp010000/ } $mech->links;

	foreach my $fund_link (@fund_links) {
		my $fund_name = $fund_link->text;
		print STDERR "$fund_name\n";
		my $fund_url  = $fund_link->url_abs;
		$mech->get($fund_url);
		my $content = $mech->content;

		my $te = HTML::TableExtract->new;
		$te->parse($content);
		my @tables = $te->tables;
		my $table= $tables[3];
		my @values = @{ $tables[3]->rows->[1] }[0..2];
		$data{$fund_name} = {
			date => $values[0],
			nav  => $values[1],
			dev  => $values[2],
		};
		printf "%-50s %-15s %-10s %-10s\n", 
			$fund_name, 
			$values[0], 
			$values[1], 
			$values[2];
	}
}
