import 'package:flutter/material.dart';

class FieldDef {
  const FieldDef(this.key, this.label);

  final String key;
  final String label;
}

/// Describes how one Liferay object definition of the Northstar space is
/// displayed and navigated.
class ContentType {
  const ContentType({
    required this.restPath,
    required this.className,
    required this.label,
    required this.singular,
    required this.description,
    required this.icon,
    required this.color,
    this.idField,
    this.facts = const [],
    this.sections = const [],
    this.links = const [],
    this.facets = const [],
  });

  /// REST path segment: `/o/c/{restPath}/scopes/{space}`.
  final String restPath;

  /// Search index class name suffix:
  /// `com.liferay.object.model.ObjectDefinition#{className}`.
  final String className;
  final String label;
  final String singular;
  final String description;
  final IconData icon;
  final Color color;

  /// Business identifier field shown as the entry's code.
  final String? idField;

  /// Short attributes shown in the detail header.
  final List<FieldDef> facts;

  /// Long (often HTML) fields rendered as sections, in order.
  final List<FieldDef> sections;

  /// Fields holding comma separated external reference codes or product
  /// codes, rendered as navigable links.
  final List<FieldDef> links;

  /// Fields offered as filters in the list view.
  final List<FieldDef> facets;
}

/// Fields that contain references (ERCs or product codes) for every type,
/// used to build the "referenced by" index.
const productCodeFields = ['productCode', 'productsUsed'];

const _audience = FieldDef('audience', 'Audience');
const _lifecycle = FieldDef('lifecycleStatus', 'Lifecycle');
const _confidentiality = FieldDef('confidentiality', 'Confidentiality');
const _country = FieldDef('countryScope', 'Country');
const _product = FieldDef('productCode', 'Product');
const _businessDomain = FieldDef('businessDomain', 'Business domain');
const _effective = FieldDef('effectiveDate', 'Effective date');

const contentTypes = <ContentType>[
  ContentType(
    restPath: 'nmgproducts',
    className: 'NMGPRODUCT',
    label: 'Products',
    singular: 'Product',
    description: 'Chargers, cloud platforms and energy solutions',
    icon: Icons.ev_station_outlined,
    color: Color(0xFF0B6E99),
    idField: 'productCode',
    facts: [
      FieldDef('productCode', 'Product code'),
      FieldDef('productFamily', 'Family'),
      FieldDef('launchDate', 'Launch date'),
      FieldDef('countryAvailability', 'Availability'),
    ],
    sections: [
      FieldDef('shortDescription', 'Overview'),
      FieldDef('fullDescription', 'Description'),
      FieldDef('keyFeatures', 'Key features'),
      FieldDef('technicalSummary', 'Technical summary'),
      FieldDef('targetMarket', 'Target market'),
    ],
    links: [FieldDef('relatedProducts', 'Related products')],
    facets: [FieldDef('productFamily', 'Family'), _lifecycle],
  ),
  ContentType(
    restPath: 'nmgsupportarticles',
    className: 'NMGSUPPORT',
    label: 'Support Articles',
    singular: 'Support article',
    description: 'Troubleshooting guides and resolutions',
    icon: Icons.support_agent_outlined,
    color: Color(0xFF2E7D32),
    idField: 'articleId',
    facts: [
      _product,
      FieldDef('relatedErrorCodes', 'Error codes'),
      _audience,
      _country,
      FieldDef('lastReviewedDate', 'Last reviewed'),
    ],
    sections: [
      FieldDef('problemStatement', 'Problem'),
      FieldDef('symptoms', 'Symptoms'),
      FieldDef('environment', 'Environment'),
      FieldDef('possibleCauses', 'Possible causes'),
      FieldDef('resolution', 'Resolution'),
      FieldDef('verificationSteps', 'Verification'),
      FieldDef('escalationCriteria', 'Escalation criteria'),
    ],
    links: [FieldDef('relatedArticles', 'Related content')],
    facets: [_product, _audience, _lifecycle],
  ),
  ContentType(
    restPath: 'nmgknownissues',
    className: 'NMGKNOWNISSUE',
    label: 'Known Issues',
    singular: 'Known issue',
    description: 'Open and fixed product defects',
    icon: Icons.bug_report_outlined,
    color: Color(0xFFC62828),
    idField: 'issueId',
    facts: [
      _product,
      FieldDef('severity', 'Severity'),
      FieldDef('issueStatus', 'Status'),
      FieldDef('affectedVersions', 'Affected versions'),
      FieldDef('fixedInVersion', 'Fixed in'),
      FieldDef('dateIdentified', 'Identified'),
      _audience,
    ],
    sections: [
      FieldDef('symptoms', 'Symptoms'),
      FieldDef('rootCause', 'Root cause'),
      FieldDef('workaround', 'Workaround'),
      FieldDef('permanentFix', 'Permanent fix'),
    ],
    links: [FieldDef('relatedSupportArticles', 'Support articles')],
    facets: [
      FieldDef('severity', 'Severity'),
      FieldDef('issueStatus', 'Status'),
      _product,
    ],
  ),
  ContentType(
    restPath: 'nmgfaqs',
    className: 'NMGFAQ',
    label: 'FAQs',
    singular: 'FAQ',
    description: 'Frequently asked questions',
    icon: Icons.quiz_outlined,
    color: Color(0xFF6A1B9A),
    facts: [
      _product,
      FieldDef('faqDomain', 'Topic'),
      _audience,
      _businessDomain,
      _effective,
    ],
    sections: [FieldDef('question', 'Question'), FieldDef('answer', 'Answer')],
    links: [FieldDef('relatedArticles', 'Related content')],
    facets: [_product, _audience, _businessDomain],
  ),
  ContentType(
    restPath: 'nmgprocedures',
    className: 'NMGPROCEDURE',
    label: 'Procedures',
    singular: 'Procedure',
    description: 'Installation and maintenance procedures',
    icon: Icons.handyman_outlined,
    color: Color(0xFFEF6C00),
    idField: 'procedureId',
    facts: [
      _product,
      FieldDef('procedureDomain', 'Domain'),
      _audience,
      _country,
      _effective,
    ],
    sections: [
      FieldDef('purpose', 'Purpose'),
      FieldDef('prerequisites', 'Prerequisites'),
      FieldDef('requiredTools', 'Required tools'),
      FieldDef('safetyWarnings', 'Safety warnings'),
      FieldDef('procedureSteps', 'Steps'),
      FieldDef('validation', 'Validation'),
      FieldDef('procTroubleshooting', 'Troubleshooting'),
      FieldDef('escalation', 'Escalation'),
    ],
    links: [FieldDef('supersedesProcedure', 'Supersedes')],
    facets: [FieldDef('procedureDomain', 'Domain'), _product, _audience],
  ),
  ContentType(
    restPath: 'nmgtechspecs',
    className: 'NMGTECHSPEC',
    label: 'Technical Specs',
    singular: 'Technical specification',
    description: 'Hardware ratings, certifications, requirements',
    icon: Icons.memory_outlined,
    color: Color(0xFF455A64),
    facts: [
      _product,
      FieldDef('hardwareVersion', 'Hardware'),
      FieldDef('inputVoltage', 'Input'),
      FieldDef('outputVoltage', 'Output'),
      FieldDef('maximumPower', 'Max power'),
      FieldDef('connectivity', 'Connectivity'),
      FieldDef('protocols', 'Protocols'),
      FieldDef('ipRating', 'IP rating'),
      FieldDef('operatingTemperature', 'Temperature'),
      FieldDef('dimensions', 'Dimensions'),
      FieldDef('weight', 'Weight'),
      _effective,
    ],
    sections: [
      FieldDef('techNotes', 'Notes'),
      FieldDef('installationRequirements', 'Installation requirements'),
      FieldDef('safetyInformation', 'Safety'),
      FieldDef('certificationInformation', 'Certifications'),
    ],
    facets: [_product, _lifecycle],
  ),
  ContentType(
    restPath: 'nmgreleasenotes',
    className: 'NMGRELEASE',
    label: 'Release Notes',
    singular: 'Release note',
    description: 'Firmware and software releases',
    icon: Icons.new_releases_outlined,
    color: Color(0xFF00838F),
    idField: 'version',
    facts: [
      FieldDef('product', 'Product'),
      FieldDef('version', 'Version'),
      FieldDef('previousVersion', 'Previous version'),
      FieldDef('releaseDate', 'Release date'),
    ],
    sections: [
      FieldDef('summary', 'Summary'),
      FieldDef('newFeatures', 'New features'),
      FieldDef('improvements', 'Improvements'),
      FieldDef('bugFixes', 'Bug fixes'),
      FieldDef('breakingChanges', 'Breaking changes'),
      FieldDef('knownIssuesText', 'Known issues'),
      FieldDef('upgradeInstructions', 'Upgrade instructions'),
    ],
    facets: [FieldDef('product', 'Product'), _lifecycle],
  ),
  ContentType(
    restPath: 'nmgpolicies',
    className: 'NMGPOLICY',
    label: 'Policies',
    singular: 'Policy',
    description: 'Compliance, HR and data protection policies',
    icon: Icons.policy_outlined,
    color: Color(0xFF283593),
    idField: 'policyId',
    facts: [
      FieldDef('policyDomain', 'Domain'),
      FieldDef('ownerDepartment', 'Owner'),
      _businessDomain,
      _audience,
      _country,
      _effective,
      FieldDef('policyReviewDate', 'Review date'),
    ],
    sections: [
      FieldDef('purpose', 'Purpose'),
      FieldDef('scope', 'Scope'),
      FieldDef('policyText', 'Policy'),
      FieldDef('responsibilities', 'Responsibilities'),
      FieldDef('exceptions', 'Exceptions'),
    ],
    links: [FieldDef('supersedesPolicy', 'Supersedes')],
    facets: [_businessDomain, _confidentiality, _lifecycle],
  ),
  ContentType(
    restPath: 'nmgcorporatearticles',
    className: 'NMGCORPORATE',
    label: 'Corporate News',
    singular: 'Corporate article',
    description: 'Announcements, strategy and internal news',
    icon: Icons.campaign_outlined,
    color: Color(0xFFAD1457),
    facts: [
      FieldDef('articleType', 'Type'),
      FieldDef('department', 'Department'),
      FieldDef('publicationDate', 'Published'),
      _audience,
      _country,
    ],
    sections: [FieldDef('summary', 'Summary'), FieldDef('body', 'Article')],
    links: [FieldDef('relatedContent', 'Related content')],
    facets: [FieldDef('articleType', 'Type'), _audience],
  ),
  ContentType(
    restPath: 'nmgcustomercases',
    className: 'NMGCASE',
    label: 'Customer Cases',
    singular: 'Customer case',
    description: 'Customer success stories',
    icon: Icons.business_outlined,
    color: Color(0xFF558B2F),
    facts: [
      FieldDef('customerName', 'Customer'),
      FieldDef('industry', 'Industry'),
      _country,
      FieldDef('deploymentSize', 'Deployment'),
      FieldDef('productsUsed', 'Products used'),
    ],
    sections: [
      FieldDef('customerChallenge', 'Challenge'),
      FieldDef('solution', 'Solution'),
      FieldDef('implementation', 'Implementation'),
      FieldDef('results', 'Results'),
      FieldDef('customerQuote', 'Customer quote'),
      FieldDef('lessonsLearned', 'Lessons learned'),
    ],
    links: [FieldDef('relatedProducts', 'Related products')],
    facets: [_country, FieldDef('industry', 'Industry')],
  ),
  ContentType(
    restPath: 'nmgsalesplaybooks',
    className: 'NMGSALES',
    label: 'Sales Playbooks',
    singular: 'Sales playbook',
    description: 'Segment playbooks for the sales team',
    icon: Icons.menu_book_outlined,
    color: Color(0xFF8D6E63),
    facts: [FieldDef('segment', 'Segment')],
    sections: [
      FieldDef('customerProfile', 'Customer profile'),
      FieldDef('customerNeeds', 'Customer needs'),
      FieldDef('valueProposition', 'Value proposition'),
      FieldDef('recommendedProducts', 'Recommended products'),
      FieldDef('exampleConfiguration', 'Example configuration'),
      FieldDef('discoveryQuestions', 'Discovery questions'),
      FieldDef('qualificationCriteria', 'Qualification criteria'),
      FieldDef('objections', 'Objections'),
      FieldDef('objectionResponses', 'Objection responses'),
      FieldDef('competitivePositioning', 'Competitive positioning'),
    ],
    links: [FieldDef('relatedCaseStudies', 'Case studies')],
    facets: [_lifecycle, _confidentiality],
  ),
];

final contentTypesByPath = {for (final t in contentTypes) t.restPath: t};

/// Resolves `com.liferay.object.model.ObjectDefinition#NMGSUPPORT` (or the
/// bare suffix) to its content type.
ContentType? contentTypeOfClass(String className) {
  final suffix = className.split('#').last;
  for (final t in contentTypes) {
    if (t.className == suffix) return t;
  }
  return null;
}
