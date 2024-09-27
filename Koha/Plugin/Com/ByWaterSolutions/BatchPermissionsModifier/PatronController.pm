package Koha::Plugin::Com::ByWaterSolutions::BatchPermissionsModifier::PatronController;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Koha::Plugin::Com::ByWaterSolutions::BatchPermissionsModifier;

=head1 API

=head2 Class Methods

=head3 Method that checks the patron, updates permissions if needed

=cut

sub check {
    my $c = shift->openapi->valid_input or return;

    my $patron_id = $c->validation->param('patron_id');
    my $patron    = Koha::Patrons->find($patron_id);

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::BatchPermissionsModifier->new();
    $plugin->check_patron( { borrowernumber => $patron_id } );

    unless ($patron) {
        return $c->render( status => 404, openapi => { error => "Patron not found." } );
    }

    return $c->render( status => 200, openapi => { success => Mojo::JSON->true } );
}

sub check_status {
    my $c = shift->openapi->valid_input or return;

    my $patron_id = $c->validation->param('patron_id');
    my $patron    = Koha::Patrons->find($patron_id);

    my $data = $c->check_patron_status( { borrowernumber => $patron_id } );

    unless ($patron) {
        return $c->render( status => 404, openapi => { error => "Patron not found." } );
    }

    return $c->render( status => 200, openapi => $data );
}

sub check_list {
    my $c = shift->openapi->valid_input or return;

    my $list_id = $c->validation->param('list_id');
#    my $patron    = Koha::Patrons->find($list_id);

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::BatchPermissionsModifier->new();
    $plugin->check_list( { list_id => $list_id } );

#    unless ($patron) {
#        return $c->render( status => 404, openapi => { error => "Patron not found." } );
#    }

    return $c->render( status => 200, openapi => { success => Mojo::JSON->true } );
}

sub check_patron_status {
    my ( $c, $params ) = @_;
    my $borrowernumber = $params->{borrowernumber};

    my $dbh = C4::Context->dbh;

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::BatchPermissionsModifier->new();
    my @pairs = split(/\r?\n/, $plugin->retrieve_data('template_permission_mappings') );

    # Check to see if patron is a template patron, if so, update the permissions
    # of all patrons in lists mapped to that patron
    my $is_template_patron;
    my @patron_list_ids;
    foreach my $pair ( @pairs ) {
        my ( $template_borrowernumber, $patron_list_id ) = split(/:[[:blank:]]{0,1}/, $pair );
        push( @patron_list_ids, $patron_list_id ) if ( $borrowernumber eq $template_borrowernumber );
    }

    my $data = {
        is_template_patron => 0,
    };

    if (@patron_list_ids) {
        $data->{is_template_patron} = 1;
        $data->{patron_lists}       = [
            Koha::Database->new()->schema->resultset('PatronList')->search(
                { patron_list_id => { -in => \@patron_list_ids } },
                { result_class => 'DBIx::Class::ResultClass::HashRefInflator' }
            )->all
        ];
    }
    else {

        foreach my $pair (@pairs) {
            my ( $template_borrowernumber, $patron_list_id ) =
              split( /:[[:blank:]]{0,1}/, $pair );

            my $count = $dbh->do(
                "SELECT borrowernumber FROM patron_list_patrons WHERE patron_list_id = ? AND borrowernumber = ?",
                undef,
                ( $patron_list_id, $borrowernumber )
            );

            if ( $count eq '1' ) {
                $data->{patron_list} =
                  Koha::Database->new()->schema->resultset('PatronList')->find(
                    $patron_list_id,
                    {
                        result_class =>
                          'DBIx::Class::ResultClass::HashRefInflator'
                    }
                  );

                my $template_patron = Koha::Patrons->find($template_borrowernumber);
                $data->{template_patron} = $c->objects->to_api($template_patron);

                last;
            }
        }
    }

    return $data;
}

1;
