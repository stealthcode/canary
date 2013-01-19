require_relative '../script_helper'

describe 'The Members Portal' do
  context 'when trying to open the Dashboard' do
    before(:each) {
      go_to_page Example::DashboardPage
    }
    it 'should load the 404 Page' do
      story.should be_on_page Example::PageNotFoundPage
    end
    context 'when the user is logged in' do
      before(:all) {
        go_to_page Example::LoginPage
        story.should be_on_page Example::LoginPage
        fill_out :username_field => 'TestUser',
                 :password_field => 'guest'
        click :login

      }
      subject {story}
      it { should be_on_page WebClient::DashboardPage }

      it 'should show the user\' full name' do
        element(:welcome_message).text.should == 'Welcome back Aaron Test'
      end

    end
  end
end