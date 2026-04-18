class ArtifactsController < ApplicationController
  def show
    artifact = Artifact.find(params[:id])
    render(json: serialize_artifact(artifact))
  end

  def create
    artifact = Artifact.create!(artifact_params)
    render(json: serialize_artifact(artifact), status: :created)
  end

  private

  def artifact_params
    params.expect(artifact: %i[user_id title location_kind location_url])
  end

  def serialize_artifact(artifact)
    {
      id: artifact.id,
      user_id: artifact.user_id,
      title: artifact.title,
      location_kind: artifact.location_kind,
      location_url: artifact.location_url,
      created_at: artifact.created_at.iso8601,
    }
  end
end
