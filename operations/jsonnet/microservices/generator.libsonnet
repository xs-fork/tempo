{
  local k = import 'ksonnet-util/kausal.libsonnet',
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,
  local deployment = k.apps.v1.deployment,
  local volume = k.core.v1.volume,

  local target_name = 'metrics-generator',
  local tempo_config_volume = 'tempo-conf',
  local tempo_overrides_config_volume = 'overrides',

  tempo_metrics_generator_container::
    container.new(target_name, $._images.tempo) +
    container.withPorts([
      containerPort.new('prom-metrics', $._config.port),
    ]) +
    container.withArgs([
      '-target=' + target_name,
      '-config.file=/conf/tempo.yaml',
      '-mem-ballast-size-mbs=' + $._config.ballast_size_mbs,
    ]) +
    container.withVolumeMounts([
      volumeMount.new(tempo_config_volume, '/conf'),
      volumeMount.new(tempo_overrides_config_volume, '/overrides'),
    ]) +
    $.util.withResources($._config.metrics_generator.resources) +
    $.util.readinessProbe,

  tempo_metrics_generator_deployment:
    deployment.new(
      target_name,
      $._config.metrics_generator.replicas,
      $.tempo_metrics_generator_container,
      {
        app: target_name,
        [$._config.gossip_member_label]: 'true',
      }
    ) +
    deployment.mixin.spec.strategy.rollingUpdate.withMaxSurge(3) +
    deployment.mixin.spec.strategy.rollingUpdate.withMaxUnavailable(1) +
    deployment.mixin.spec.template.metadata.withAnnotations({
      config_hash: std.md5(std.toString($.tempo_metrics_generator_configmap.data['tempo.yaml'])),
    }) +
    deployment.mixin.spec.template.spec.withVolumes([
      volume.fromConfigMap(tempo_config_volume, $.tempo_metrics_generator_configmap.metadata.name),
      volume.fromConfigMap(tempo_overrides_config_volume, $._config.overrides_configmap_name),
    ]),

  tempo_metrics_generator_service:
    k.util.serviceFor($.tempo_metrics_generator_deployment),
}
