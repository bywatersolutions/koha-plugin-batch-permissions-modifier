package Koha::Plugin::Com::ByWaterSolutions::BatchPermissionsModifier;

## It's good practive to use Modern::Perl
use Modern::Perl;

use Mojo::JSON;

## Required for all plugins
use base qw(Koha::Plugins::Base);

use Koha::Patrons;
use Koha::List::Patron;
use Koha::Logger;
use Koha::Database;

## Here we set our plugin version
our $VERSION = "{VERSION}";

our $metadata = {
    name            => 'Batch Patron Permissions Modifier',
    author          => 'Kyle M Hall',
    description     => 'A Koha plugin that adds the ability to set patron permissions in bulk.',
    date_authored   => '2018-02-26',
    date_updated    => '1900-01-01',
    minimum_version => '16.05',
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    # Need to set up initial use of versioning
    my $installed        = $self->retrieve_data('__INSTALLED__');
    my $database_version = $self->retrieve_data('__INSTALLED_VERSION__');
    my $plugin_version   = $self->get_metadata->{version};
    if ( $installed && !$database_version ) {
        $self->upgrade();
        $self->store_data( { '__INSTALLED_VERSION__' => $plugin_version } );
    }

    return $self;
}

sub upgrade {
    my ( $self, $args ) = @_;

    my $version = $self->retrieve_data('__INSTALLED_VERSION__');

    my $dbh = C4::Context->dbh;

    if ( !$version ) {
        $dbh->do(q{
	        DELETE FROM permissions WHERE module_bit = 19 AND code IN ('check_list', 'check_patron');
    	});

        $dbh->do(q{
	        DELETE FROM user_permissions WHERE module_bit = 19 AND code IN ('check_list', 'check_patron');
    	});
    }

    return 1;
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec = Mojo::JSON::decode_json $spec_str;

    return $spec;
}

sub api_namespace {
    my ($self) = @_;

    return 'bpm';
}

sub admin {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('submitted') ) {
        $self->tool_step1();
    }
    else {
        $self->tool_step2();
    }
}

sub tool_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'tool-step1.tt' });

    my @borrowernumbers = split(/\r?\n/, $self->retrieve_data('template_patrons') );

    my $patrons = Koha::Patrons->search({ borrowernumber => { -in => \@borrowernumbers } });
    my $lists = Koha::List::Patron::GetPatronLists();

    $template->param(
        template_patrons => $patrons,
        patron_lists     => $lists,
    );

    print $cgi->header(
        {
            -type     => 'text/html',
            -charset  => 'UTF-8',
            -encoding => "UTF-8"
        }
    );
    print $template->output();
}

sub tool_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'tool-step2.tt' });

    my $borrowernumber = $cgi->param('borrowernumber');
    my $patron_list_id = $cgi->param('patron_list_id');

    my $patron = Koha::Patrons->find( $borrowernumber );

    if ($patron) {
        my $count = $self->update_permissions( $patron, $patron_list_id );
        $template->param(
            patrons_updated => $count,
            patron => $patron,
            patron_list => $patron_list_id
        );
    }

    print $cgi->header(
        {
            -type     => 'text/html',
            -charset  => 'UTF-8',
            -encoding => "UTF-8"
        }
    );
    print $template->output();
}

sub check_patron {
    my ( $self, $params ) = @_;
    my $borrowernumber = $params->{borrowernumber};

    sleep 3;

    my $librarian = C4::Context->userenv ? C4::Context->userenv->{'number'} : undef,
    my $logger = Koha::Logger->get;

    my $dbh = C4::Context->dbh;

    my @pairs = split(/\r?\n/, $self->retrieve_data('template_permission_mappings') );

    # Check to see if patron is a template patron, if so, update the permissions
    # of all patrons in lists mapped to that patron
    my $is_template_patron;
    foreach my $pair ( @pairs ) {
        my ( $template_borrowernumber, $patron_list_id ) = split(/:[[:blank:]]{0,1}/, $pair );

        my $template_patron;
        if ( $borrowernumber eq $template_borrowernumber ) {
            $template_patron ||= Koha::Patrons->find( $template_borrowernumber );
            $self->update_permissions( $template_patron, $patron_list_id );
            $is_template_patron = 1;
	    $logger->debug("BatchPermissionsModifier ( librarian: $librarian ): borrowernumber $borrowernumber is a template patron, updating related patron permissions");
        }
    }

    # If this patron is not a template patron, check to see if the patron is any of
    # the mapped patron lists and set the patrons permissions based on the first mapped
    # list the patron is found in. Stop at the first list the patron is found in.
    unless ( $is_template_patron ) {
        foreach my $pair ( @pairs ) {
            my ( $template_borrowernumber, $patron_list_id ) = split(/:[[:blank:]]{0,1}/, $pair );

            my $count = $dbh->do("SELECT borrowernumber FROM patron_list_patrons WHERE patron_list_id = ? AND borrowernumber = ?", undef, ( $patron_list_id, $borrowernumber ) );

            if ( $count eq '1' ) {
                $logger->debug("BatchPermissionsModifier ( librarian: $librarian ): borrowernumber $borrowernumber is in a mapped patron list, updated permissions");
                my $template_patron = Koha::Patrons->find( $template_borrowernumber );
                $self->update_permissions( $template_patron, $patron_list_id );

                last;
            }
        }
    }
}

sub check_list {
    my ( $self, $params ) = @_;
    my $list_id = $params->{list_id};

    sleep 3;

    my $dbh = C4::Context->dbh;

    my @pairs = split(/\r?\n/, $self->retrieve_data('template_permission_mappings') );

    foreach my $pair ( @pairs ) {
        my ( $template_borrowernumber, $patron_list_id ) = split(/:[[:blank:]]{0,1}/, $pair );

        next unless $list_id eq $patron_list_id;

        my $template_patron = Koha::Patrons->find( $template_borrowernumber );
        $self->update_permissions( $template_patron, $patron_list_id );

        last;
    }
}

sub update_permissions {
    my ( $self, $patron, $patron_list_id ) = @_;

    my $librarian = C4::Context->userenv ? C4::Context->userenv->{'number'} : undef,
    my $logger = Koha::Logger->get;
    $logger->debug("BatchPermissionsModifier ( librarian: $librarian ): update permissions for list $patron_list_id based on patron " . $patron->id);

    my $dbh = C4::Context->dbh;

    # Update borrowers.flags
    my $count = $dbh->do(
        'UPDATE patron_list_patrons LEFT JOIN borrowers USING ( borrowernumber ) SET borrowers.flags = ? WHERE patron_list_id = ?',
        undef,
        ( $patron->flags, $patron_list_id )
    );

    # Update user_permissions table
    ## First, delete any permissions the template patron *doesn't* have
    $dbh->do(
        'DELETE FROM user_permissions
         WHERE borrowernumber IN ( SELECT borrowernumber FROM patron_list_patrons WHERE patron_list_id = ? )',
#        AND code NOT IN ( SELECT * FROM (SELECT code FROM user_permissions WHERE borrowernumber = ? ) AS tmp )',
        undef,
        ( $patron_list_id )#, $patron->id )
    );
    ## Second, create any new permissions needed that the patron doesn't have, but the template patron does have
    ## Neither INSERT IGNORE, nor REPLACE INTO seem to work here, causing duplicate user_permissions, hence the delete aboves
    $dbh->do(
        'INSERT INTO user_permissions SELECT patron_list_patrons.borrowernumber, module_bit, code FROM patron_list_patrons, user_permissions WHERE patron_list_id = ? AND user_permissions.borrowernumber = ?',
        undef,
        ( $patron_list_id, $patron->id )
    );

    return $count + 0;
}


sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $dbh = C4::Context->dbh;

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        my $query = q{SELECT * FROM plugin_data WHERE plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::BatchPermissionsModifier'};
        my $sth = $dbh->prepare( $query );
        $sth->execute();
        my $data;
        while ( my $r = $sth->fetchrow_hashref ) {
            $data->{ $r->{plugin_key} } = $r->{plugin_value}
        }

        $template->param(%$data);

        print $cgi->header(
            {
                -type     => 'text/html',
                -charset  => 'UTF-8',
                -encoding => "UTF-8"
            }
        );
        print $template->output();
    }
    else {
        my $data = { $cgi->Vars };
        delete $data->{ $_ } for qw( method save class );

        $dbh->do(q{DELETE FROM plugin_data WHERE plugin_key LIKE "enable%" AND plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::BatchPermissionsModifier'});
        $self->store_data($data);

        $self->update_intranetuser_js($data);

        $self->go_home();
    }
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;
}

sub intranet_js {
    my ( $self ) = @_;
    my $script = $self->retrieve_data('intranetuser_js');
    return $script ? "<script>$script</script>" : q{};
}

sub update_intranetuser_js {
    my ($self, $data) = @_;

    my $template = $self->get_template( { file => 'intranetuserjs.tt' } );
    $template->param(%$data);

    my $intranetuser_js = $template->output();
    
    $self->store_data({ intranetuser_js => $intranetuser_js });
}

1;
