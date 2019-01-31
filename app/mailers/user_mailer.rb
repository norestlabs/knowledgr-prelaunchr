class UserMailer < ActionMailer::Base
  default from: "Knowledgr <team@knowledgr.co>"

  def signup_email(user)
    @user = user
    @twitter_message = "A scientific revolution is coming. Click here to join the waiting list, by invite only link."

    mail(:to => user.email, :subject => "Thanks for signing up!")
  end
end
