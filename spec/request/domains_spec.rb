require 'spec_helper'

RSpec.describe 'Domains Request' do
  let(:user) { VCAP::CloudController::User.make }
  let(:user_header) { headers_for(user, email: user_email, user_name: user_name) }
  let(:space) { VCAP::CloudController::Space.make }
  let(:user_email) { Sham.email }
  let(:user_name) { 'some-username' }
  let(:org) { space.organization }

  before do
    org.add_user(user)
    space.add_developer(user)
    VCAP::CloudController::Domain.dataset.destroy
  end

  describe 'GET /v3/domains' do
    let(:headers) { headers_for(user) }

    let!(:shared_domain) { VCAP::CloudController::SharedDomain.make(name: 'my-domain.edu', guid: 'shared_domain') }
    let!(:private_domain) { VCAP::CloudController::PrivateDomain.make(name: 'my-private-domain.edu', owning_organization: org, guid: 'private_domain') }

    let(:org2) { VCAP::CloudController::Organization.make }
    let(:org3) { VCAP::CloudController::Organization.make }

    before do
      set_current_user_as_role(org: org2, user: user, role: 'org_manager')
      org2.add_private_domain(private_domain)
      org3.add_private_domain(private_domain)
    end

    it 'lists all domains with filtered shared_orgs' do
      get '/v3/domains', nil, headers

      expect(last_response.status).to eq(200)

      parsed_response = MultiJson.load(last_response.body)
      expect(parsed_response).to be_a_response_like(
        {
          'pagination' => {
            'total_results' => 2,
            'total_pages' => 1,
            'first' => {
              'href' => "#{link_prefix}/v3/domains?page=1&per_page=50"
            },
            'last' => {
              'href' => "#{link_prefix}/v3/domains?page=1&per_page=50"
            },
            'next' => nil,
            'previous' => nil
          },
          'resources' => [
            {
              'guid' => 'shared_domain',
              'created_at' => iso8601,
              'updated_at' => iso8601,
              'name' => 'my-domain.edu',
              'internal' => false,
              'relationships' => {
                'organization' => {
                  'data' => nil
                },
                'shared_organizations' => {
                  'data' => []
                }
              },
              'links' => {
                'self' => { 'href' => "#{link_prefix}/v3/domains/shared_domain" }
              }
            },
            {
              'guid' => 'private_domain',
              'created_at' => iso8601,
              'updated_at' => iso8601,
              'name' => 'my-private-domain.edu',
              'internal' => false,
              'relationships' => {
                'organization' => {
                  'data' => {
                    'guid' => org.guid
                  }
                },
                'shared_organizations' => {
                  'data' => [{ 'guid' => org2.guid }]
                }
              },
              'links' => {
                'self' => { 'href' => "#{link_prefix}/v3/domains/private_domain" }
              }
            }
          ]
        }
      )
    end
  end

  describe 'POST /v3/domains' do
    context 'when not authenticated' do
      it 'returns 401' do
        params = {}
        headers = {}

        post '/v3/domains', params, headers

        expect(last_response.status).to eq(401)
      end
    end

    context 'when authenticated but not admin' do
      let(:params) do
        {
          name: 'my-domain.biz',
          relationships: {
            organization: {
              data: {
                guid: org.guid
              }
            }
          },
        }
      end

      context 'when org manager' do
        before do
          set_current_user_as_role(role: 'org_manager', org: org, user: user)
        end

        let(:headers) { headers_for(user) }

        context 'when the feature flag is enabled' do
          it 'returns a 201 and creates a private domain' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(201)

            domain = VCAP::CloudController::PrivateDomain.last

            expected_response = {
              'name' => params[:name],
              'internal' => false,
              'guid' => domain.guid,
              'relationships' => {
                'organization' => {
                  'data' => {
                    'guid' => org.guid
                  }
                },
                'shared_organizations' => {
                  'data' => []
                }
              },
              'created_at' => iso8601,
              'updated_at' => iso8601,
              'links' => {
                'self' => {
                  'href' => "#{link_prefix}/v3/domains/#{domain.guid}"
                }
              }
            }
            expect(parsed_response).to be_a_response_like(expected_response)
          end
        end

        context 'when the org is suspended' do
          before do
            org.status = 'suspended'
            org.save
          end
          it 'returns a 403' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(403)
          end
        end

        context 'when the feature flag is disabled' do
          let!(:feature_flag) { VCAP::CloudController::FeatureFlag.make(name: 'private_domain_creation', enabled: false) }
          it 'returns a 403' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(403)
          end
        end
      end

      context 'when not an org manager' do
        let(:user) { VCAP::CloudController::User.make }
        let(:headers) { headers_for(user) }

        it 'returns 403' do
          post '/v3/domains', params.to_json, headers

          expect(last_response.status).to eq(403)
        end
      end
    end

    context 'when authenticated and admin' do
      let(:user) { VCAP::CloudController::User.make }
      let(:headers) { admin_headers_for(user) }
      context 'when creating a shared domain' do
        context 'when provided valid arguments' do
          let(:params) do
            {
              name: 'my-domain.biz',
              internal: true,
            }
          end

          it 'returns 201' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(201)

            domain = VCAP::CloudController::Domain.last

            expected_response = {
              'name' => params[:name],
              'internal' => params[:internal],
              'guid' => domain.guid,
              'created_at' => iso8601,
              'updated_at' => iso8601,
              'relationships' => {
                'organization' => {
                  'data' => nil
                },
                'shared_organizations' => {
                  'data' => [],
                }
              },
              'links' => {
                'self' => {
                  'href' => "#{link_prefix}/v3/domains/#{domain.guid}"
                }
              }
            }
            expect(parsed_response).to be_a_response_like(expected_response)
          end
        end

        context 'when provided invalid arguments' do
          let(:params) do
            {
              name: "#{'f' * 63}$"
            }
          end

          it 'returns 422' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(422)

            expected_err = ['Name does not comply with RFC 1035 standards',
                            'Name must contain at least one "."',
                            'Name subdomains must each be at most 63 characters',
                            'Name must consist of alphanumeric characters and hyphens']
            expect(parsed_response['errors'][0]['detail']).to eq expected_err.join(', ')
          end
        end
      end

      context 'when creating a private domain' do
        context 'when params are valid' do
          let(:params) do
            {
              name: 'my-domain.biz',
              relationships: {
                organization: {
                  data: {
                    guid: org.guid
                  }
                }
              },
            }
          end

          it 'returns a 201 and creates a private domain' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(201)

            domain = VCAP::CloudController::PrivateDomain.last

            expected_response = {
              'name' => params[:name],
              'internal' => false,
              'guid' => domain.guid,
              'relationships' => {
                'organization' => {
                  'data' => {
                    'guid' => org.guid
                  }
                },
                'shared_organizations' => {
                  'data' => [],
                }
              },
              'created_at' => iso8601,
              'updated_at' => iso8601,
              'links' => {
                'self' => {
                  'href' => "#{link_prefix}/v3/domains/#{domain.guid}"
                }
              }
            }
            expect(parsed_response).to be_a_response_like(expected_response)
          end
        end

        context 'when the params are invalid' do
          context 'creating a sub domain of a domain scoped to another organization' do
            let(:organization_to_scope_to) { VCAP::CloudController::Organization.make }
            let(:existing_scoped_domain) { VCAP::CloudController::PrivateDomain.make }

            let(:params) do
              {
                name: "foo.#{existing_scoped_domain.name}",
                relationships: {
                  organization: {
                    data: {
                      guid: organization_to_scope_to.guid
                    }
                  }
                }
              }
            end

            it 'returns a 422 and an error' do
              post '/v3/domains', params.to_json, headers

              expect(last_response.status).to eq(422)

              expect(parsed_response['errors'][0]['detail']).to eq "The domain name \"#{params[:name]}\""\
" cannot be created because \"#{existing_scoped_domain.name}\" is already reserved by another domain"
            end
          end

          context 'when the org doesnt exist' do
            let(:params) do
              {
                name: 'my-domain.biz',
                relationships: {
                  organization: {
                    data: {
                      guid: 'non-existent-guid'
                    }
                  }
                }
              }
            end

            it 'returns a 422 and a helpful error message' do
              post '/v3/domains', params.to_json, headers

              expect(last_response.status).to eq(422)

              expect(parsed_response['errors'][0]['detail']).to eq 'Organization with guid \'non-existent-guid\' does not exist or you do not have access to it.'
            end
          end

          context 'when the org has exceeded its private domains quota' do
            let(:params) do
              {
                name: 'my-domain.biz',
                relationships: {
                  organization: {
                    data: {
                      guid: org.guid
                    }
                  }
                }
              }
            end
            it 'returns a 422 and a helpful error message' do
              org.update(quota_definition: VCAP::CloudController::QuotaDefinition.make(total_private_domains: 0))

              post '/v3/domains', params.to_json, headers

              expect(last_response.status).to eq(422)

              expect(parsed_response['errors'][0]['detail']).to eq "The number of private domains exceeds the quota for organization \"#{org.name}\""
            end
          end
        end

        context 'when the domain is in the list of reserved private domains' do
          let(:params) do
            {
              name: 'com.ac',
              relationships: {
                organization: {
                  data: {
                    guid: org.guid
                  }
                }
              }
            }
          end

          before(:each) do
            TestConfig.override({ reserved_private_domains: File.join(Paths::FIXTURES, 'config/reserved_private_domains.dat') })
          end

          it 'returns a 422 with a error message about reserved domains' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(422)

            expect(parsed_response['errors'][0]['detail']).to eq 'The "com.ac" domain is reserved and cannot be used for org-scoped domains.'
          end
        end
      end

      describe 'collisions' do
        context 'with an existing domain' do
          let!(:existing_domain) { VCAP::CloudController::SharedDomain.make }

          let(:params) do
            {
              name: existing_domain.name,
            }
          end

          it 'returns 422' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(422)

            expect(parsed_response['errors'][0]['detail']).to eq "The domain name \"#{existing_domain.name}\" is already in use"
          end
        end

        context 'with an existing route' do
          let(:existing_domain) { VCAP::CloudController::SharedDomain.make }
          let(:existing_route) { VCAP::CloudController::Route.make(domain: existing_domain) }
          let(:domain_name) { existing_route.fqdn }

          let(:params) do
            {
              name: domain_name,
            }
          end

          it 'returns 422' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(422)

            expect(parsed_response['errors'][0]['detail']).to match(
              /The domain name "#{domain_name}" cannot be created because "#{existing_route.fqdn}" is already reserved by a route/
            )
          end
        end

        context 'with an existing route as a subdomain' do
          let(:existing_route) { VCAP::CloudController::Route.make }
          let(:domain) { "sub.#{existing_route.fqdn}" }

          let(:params) do
            {
              name: domain,
            }
          end

          it 'returns 422' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(422)

            expect(parsed_response['errors'][0]['detail']).to match(
              /The domain name "#{domain}" cannot be created because "#{existing_route.fqdn}" is already reserved by a route/
            )
          end
        end

        context 'with an existing unscoped domain as a subdomain' do
          let(:existing_domain) { VCAP::CloudController::SharedDomain.make }
          let(:domain) { "sub.#{existing_domain.name}" }

          let(:params) do
            {
              name: domain,
            }
          end

          it 'returns 201' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(201)

            expect(parsed_response['name']).to eq domain
          end
        end

        context 'with an existing scoped domain as a subdomain' do
          let(:existing_domain) { VCAP::CloudController::PrivateDomain.make }
          let(:domain) { "sub.#{existing_domain.name}" }

          let(:params) do
            {
              name: domain,
            }
          end

          it 'returns 422' do
            post '/v3/domains', params.to_json, headers

            expect(last_response.status).to eq(422)

            expect(parsed_response['errors'][0]['detail']).to eq(
              %{The domain name "#{domain}" cannot be created because "#{existing_domain.name}" is already reserved by another domain}
            )
          end
        end
      end
    end
  end

  describe 'GET /v3/domains/:guid' do
    context 'when authenticated' do
      context 'when the domain is shared and exists' do
        let(:shared_domain) { VCAP::CloudController::SharedDomain.make }

        it 'returns 200 and the domain' do
          params = {}
          get "/v3/domains/#{shared_domain.guid}", params, user_header

          expect(last_response.status).to eq(200)
          expect(parsed_response).to be_a_response_like(
            {
              'guid' => shared_domain.guid,
              'created_at' => iso8601,
              'updated_at' => iso8601,
              'name' => shared_domain.name,
              'internal' => shared_domain.internal,
              'relationships' => {
                'organization' => {
                  'data' => nil },
                'shared_organizations' => {
                  'data' => [] } },
              'links' => {
                'self' => { 'href' => "#{link_prefix}/v3/domains/#{shared_domain.guid}" }
              }
            }
          )
        end
      end

      context 'when the domain is private' do
        context 'domain scoped to an org the user can read' do
          let(:private_domain) { VCAP::CloudController::PrivateDomain.make(owning_organization: org) }

          context 'domain not shared with any other org' do
            it 'returns 200 and the domain without any shared orgs' do
              params = {}
              get "/v3/domains/#{private_domain.guid}", params, user_header

              expect(last_response.status).to eq(200)
              expect(parsed_response).to be_a_response_like(
                {
                  'guid' => private_domain.guid,
                  'created_at' => iso8601,
                  'updated_at' => iso8601,
                  'name' => private_domain.name,
                  'internal' => private_domain.internal,
                  'relationships' => {
                    'organization' => {
                      'data' => { 'guid' => org.guid.to_s } },
                    'shared_organizations' => { 'data' => [] } },
                  'links' => {
                    'self' => { 'href' => "#{link_prefix}/v3/domains/#{private_domain.guid}" }
                  }
                }
              )
            end
          end

          context 'domain shared with org that user has read permissions for' do
            let(:org2) { VCAP::CloudController::Organization.make }

            before do
              set_current_user_as_role(org: org2, user: user, role: 'org_manager')
              org2.add_private_domain(private_domain)
            end

            it 'returns 200 and the domain with the shared org' do
              params = {}
              get "/v3/domains/#{private_domain.guid}", params, user_header

              expect(last_response.status).to eq(200)
              expect(parsed_response).to be_a_response_like(
                {
                  'guid' => private_domain.guid,
                  'created_at' => iso8601,
                  'updated_at' => iso8601,
                  'name' => private_domain.name,
                  'internal' => private_domain.internal,
                  'relationships' => {
                    'organization' => {
                      'data' => { 'guid' => org.guid } },
                    'shared_organizations' => { 'data' => [
                      { 'guid' => org2.guid }
                    ] } },
                  'links' => {
                    'self' => { 'href' => "#{link_prefix}/v3/domains/#{private_domain.guid}" }
                  }
                }
              )
            end
          end

          context 'domain shared with org that user does not have read permissions for' do
            let(:org2) { VCAP::CloudController::Organization.make }

            before do
              org2.add_private_domain(private_domain)
            end

            it 'returns 200 and the domain without any shared orgs' do
              params = {}
              get "/v3/domains/#{private_domain.guid}", params, user_header

              expect(last_response.status).to eq(200)
              expect(parsed_response).to be_a_response_like(
                {
                  'guid' => private_domain.guid,
                  'created_at' => iso8601,
                  'updated_at' => iso8601,
                  'name' => private_domain.name,
                  'internal' => private_domain.internal,
                  'relationships' => {
                    'organization' => {
                      'data' => { 'guid' => org.guid } },
                    'shared_organizations' => { 'data' => [] } },
                  'links' => {
                    'self' => { 'href' => "#{link_prefix}/v3/domains/#{private_domain.guid}" }
                  }
                }
              )
            end
          end
        end
      end
    end
  end
end
