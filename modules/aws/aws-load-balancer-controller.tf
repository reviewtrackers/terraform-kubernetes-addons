locals {
  aws-load-balancer-controller = merge(
    local.helm_defaults,
    {
      name                      = "aws-load-balancer-controller"
      namespace                 = "aws-load-balancer-controller"
      chart                     = "aws-load-balancer-controller"
      repository                = "https://aws.github.io/eks-charts"
      service_account_name      = "aws-load-balancer-controller"
      create_iam_resources_irsa = true
      enabled                   = false
      chart_version             = "1.0.5"
      version                   = "v2.0.0"
      iam_policy_override       = ""
      default_network_policy    = true
    },
    var.aws-load-balancer-controller
  )

  values_aws-load-balancer-controller = <<VALUES
image:
  tag: "${local.aws-load-balancer-controller["version"]}"
clusterName: ${var.cluster-name}
rbac:
  serviceAccount:
    name: "${local.aws-load-balancer-controller["version"]}"
    annotations:
      eks.amazonaws.com/role-arn: "${local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["create_iam_resources_irsa"] ? module.iam_assumable_role_aws-load-balancer-controller.this_iam_role_arn : ""}"
VALUES
}

module "iam_assumable_role_aws-load-balancer-controller" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "~> v3.0"
  create_role                   = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["create_iam_resources_irsa"]
  role_name                     = "tf-${var.cluster-name}-${local.aws-load-balancer-controller["name"]}-irsa"
  provider_url                  = replace(var.eks["cluster_oidc_issuer_url"], "https://", "")
  role_policy_arns              = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["create_iam_resources_irsa"] ? [aws_iam_policy.eks-alb-ingress[0].arn] : []
  oidc_fully_qualified_subjects = ["system:serviceaccount:${local.aws-load-balancer-controller["namespace"]}:${local.aws-load-balancer-controller["service_account_name"]}"]
}

resource "aws_iam_policy" "eks-alb-ingress" {
  count  = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["create_iam_resources_irsa"] ? 1 : 0
  name   = "tf-${var.cluster-name}-${local.aws-load-balancer-controller["name"]}"
  policy = local.aws-load-balancer-controller["iam_policy_override"] == "" ? file("${path.module}/iam/aws-load-balancer-controller.json") : local.aws-load-balancer-controller["iam_policy_override"]
}

resource "kubernetes_namespace" "aws-load-balancer-controller" {
  count = local.aws-load-balancer-controller["enabled"] ? 1 : 0

  metadata {
    labels = {
      name = local.aws-load-balancer-controller["namespace"]
    }

    name = local.aws-load-balancer-controller["namespace"]
  }
}

resource "helm_release" "aws-load-balancer-controller" {
  count                 = local.aws-load-balancer-controller["enabled"] ? 1 : 0
  repository            = local.aws-load-balancer-controller["repository"]
  name                  = local.aws-load-balancer-controller["name"]
  chart                 = local.aws-load-balancer-controller["chart"]
  version               = local.aws-load-balancer-controller["chart_version"]
  timeout               = local.aws-load-balancer-controller["timeout"]
  force_update          = local.aws-load-balancer-controller["force_update"]
  recreate_pods         = local.aws-load-balancer-controller["recreate_pods"]
  wait                  = local.aws-load-balancer-controller["wait"]
  atomic                = local.aws-load-balancer-controller["atomic"]
  cleanup_on_fail       = local.aws-load-balancer-controller["cleanup_on_fail"]
  dependency_update     = local.aws-load-balancer-controller["dependency_update"]
  disable_crd_hooks     = local.aws-load-balancer-controller["disable_crd_hooks"]
  disable_webhooks      = local.aws-load-balancer-controller["disable_webhooks"]
  render_subchart_notes = local.aws-load-balancer-controller["render_subchart_notes"]
  replace               = local.aws-load-balancer-controller["replace"]
  reset_values          = local.aws-load-balancer-controller["reset_values"]
  reuse_values          = local.aws-load-balancer-controller["reuse_values"]
  skip_crds             = local.aws-load-balancer-controller["skip_crds"]
  verify                = local.aws-load-balancer-controller["verify"]
  values = [
    local.values_aws-load-balancer-controller,
    local.aws-load-balancer-controller["extra_values"]
  ]
  namespace = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]

  depends_on = [
    helm_release.prometheus_operator
  ]
}

resource "kubernetes_network_policy" "aws-load-balancer-controller_default_deny" {
  count = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]}-default-deny"
    namespace = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "aws-load-balancer-controller_allow_namespace" {
  count = local.aws-load-balancer-controller["enabled"] && local.aws-load-balancer-controller["default_network_policy"] ? 1 : 0

  metadata {
    name      = "${kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]}-allow-namespace"
    namespace = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]
  }

  spec {
    pod_selector {
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.aws-load-balancer-controller.*.metadata.0.name[count.index]
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}
